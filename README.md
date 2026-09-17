# RetinaSense

Screening decision-support for diabetic retinopathy (DR) — **SIH 2026 PS 26038**.

RetinaSense ingests a single fundus photo, runs it through a **deterministic
image quality gate** (the differentiator: it explains *how* to retake a bad
image), grades DR severity with a benchmark-driven CNN, calibrates its
confidence, explains its attention, and hands the result to an ophthalmologist
for the final referral decision — with a parallel Simulink district-scale
capacity model. Detailed design: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
and the PRD.

> Status: **The real trained DR model is the screening default.** ResNet-50
> fine-tuned on APTOS 2019 plus temperature calibration (`data/models/`) is
> loaded by `scripts/runPipeline.m` unless mock is explicitly requested
> (`'mock', true` / `RETINASENSE_SIMULATION=mock`, tests/demo only). The
> honest benchmark record (`data/models/backbone_benchmark.json`) shows the
> clinical acceptance targets are **not yet met**, so no performance claim is
> made.

---

## 1. Project purpose

- **Screening**, not diagnosis: the output is an evidence-based grading plus a
  final **referral decision** for the full retina/ophthalmology pathway.
- The **quality gate is the entry gate**. Good/borderline/ungradable →
  actionable recapture feedback is a first-class feature.
- **Calibrated confidence**: raw softmax is never treated as certainty
  (temperature scaling, uncertainty routing → mandatory human review).
- **Human-in-the-loop**: the final call is the ophthalmologist's
  (approve / override / recapture).
- **Proof of capacity**: the Simulink/SimEvents model (with `simulink/`)
  checks — from measured full-workday simulation output, persisted to
  `simulink/output/*.json` — whether a district node can serve
  ~100,000 patients/year (~274/day). See `simulink/README.md`.

## 2. Architecture (short version)

```
Image → [Quality Gate] ─ borderline → {Enhance → Re-check} → [passed]
        ungradable → Recapture feedback (exit early)
[passed] → Retinal/Lesion Analysis (ADVISORY, never blocks)
         → DR Grading (5-class, referable = Level 2+)
         → Grad-CAM + Calibrated confidence/uncertainty
         → Human Review (approve/override/recapture)
         → Report + referral decision
```

Everything flows through a single shared **`Case` struct** (see
`core/newCase.m`). Every module implements one **stable interface contract**
(`docs/ARCHITECTURE.md §4`) with explicit input, output, error, and config.
`scripts/runPipeline.m` wires them in order.

## 3. How to run the mock pipeline

These mock scenarios need no datasets and no trained model — everything is
synthetic and deterministic.

```matlab
% add the repo root + folders to the path (path shown is an example;
% the repo is relocatable - config/paths.m computes the root automatically)
cd('<path-to-repo>/RetinaSense');
addpath(genpath(cwd));

% run the three gate scenarios end-to-end (good / borderline / ungradable)
demo_mock_pipeline

% or run a single case:
c = runPipeline('scenario', 'good');          disp(c.report.summary);
c = runPipeline('scenario', 'borderline');    disp(c.pipeline.stages);
c = runPipeline('scenario', 'ungradable');    disp(c.quality.recapture);

% launch the ophthalmologist review UI (approve / override / recapture):
launchRetinaSenseApp('good')   % also 'borderline' | 'ungradable'
app = RetinaSenseApp(runPipeline('scenario','good'));   % review a specific case

% ingest a real file (the committed synthetic demo image):
meta = struct('patientId','P1','eye','left','timestamp', datestr(now), 'phcId','PHC-X');
c = runPipeline(meta, fullfile('assets','synthetic_fundus_demo.png'));

% simulate an ophthalmologist override:
c = runPipeline('scenario','good', struct('action','override','graderId','OPH-1', ...
    'overrideGrade', 3, 'notes', 'MAs seen on evidence overlay.'));
```

Reports are written to `output/`.

### Running from a machine without MATLAB

The repo is MATLAB-first. For CI/machines without MATLAB, a lightweight,
dependency-free mirror of the mock pipeline and its contract tests lives in
`tools/python_verifier/` (dev-time only, not product code):

```bash
python tools/python_verifier/mock_pipeline.py
```

### Running the tests (MATLAB)

```matlab
results = runtests('tests')
table(results)
```

Unit tests cover the `Case` schema, config, every §4 module interface, and
pipeline orchestration.

## 4. Repository structure

```
RetinaSense/
├─ README.md / AGENTS.md
├─ config/                paths.m (roots) + experiment_config.m & sub-configs
│                         quality/preprocess/classification thresholds
├─ core/                  shared: newCase (Case schema), logging, errors
├─ preprocessing/         Stages 0-4: ingest, assessQuality, recapture,
│                         enhanceImage, recheckQuality
├─ analysis/              Stage 5 advisory: vessels/disc/fovea/lesions
├─ classification/        Stage 6: classifyImage (real path + honest mock fallback)
├─ explainability/        Stage 7: computeGradCAM (attention, honest)
├─ calibration/           Stage 8: fitTemperature + applyCalibration (entropy)
├─ reporting/             Stage 9: submitReview, buildReport, renderReport
├─ ui/                    App Designer review UI (Sprint 5)
├─ evaluation/            Stage 10: metrics.m (real math) + runValidation/ablation
├─ simulink/              District-scale SimEvents model (Sprint 6) + scenario params
├─ scripts/               runPipeline (orchestrator), demo, benchmark stub
├─ data/                  raw+processed (gitignored), manifests (committed)
├─ tests/                 unit/ + integration/ (MATLAB)
├─ tools/python_verifier/ MATLAB-less CI mirror of the mock pipeline
├─ assets/                small synthetic demo image (committed)
└─ docs/                  PRD + ARCHITECTURE (authoritative)
```

## 5. Ownership units — how teammates add/replace modules

Each folder is one owner and owns one **stable contract** (§4). Modules develop
independently on the `Case` struct; nothing else is shared.

| Owner | Folder | Contract |
|---|---|---|
| quality | `preprocessing/` | `assessQuality` (+ recapture/enhance/recheck) |
| classifier | `classification/` | `classifyImage` |
| explainability | `explainability/` | `computeGradCAM` |
| calibration | `calibration/` | `applyCalibration` / `fitTemperature` |
| analysis | `analysis/` | `analyzeRetina` (advisory, non-blocking) |
| reporting + UI | `reporting/`, `ui/` | `buildReport` + `submitReview` |
| evaluation | `evaluation/` | `metrics.m` etc. |
| simulation | `simulink/` | scenarios + capacity |

**To add a new module:** create a function that (a) has the exact contract
signature from `docs/ARCHITECTURE.md §4`, (b) reads/writes only `Case` fields,
(c) reads its config from `config/`, (d) uses `core/raiseError.m` with a
`RetinaSense:<module>:<code>` identifier, (e) is your folder's clear boundary.

**To build the real ML pipeline behind a stable contract:** keep the function
name + I/O and the `Case` fields identical, then replace each honest stub's
algorithm with the real one. Keep it honest:
- Replace `mockGrading` in `classifyImage` after `trainClassifier` +
  `benchmark_backbones` choose the backbone.
- Replace `computeGradCAM`'s zero map with `gradCAM(...)` (Sprint 4).
- Wire `fitTemperature` (Sprint 3).
- Pipeline **refuses to run with `mock=false` unless a trained model exists**
  (no silent fake output). TODO markers in each file point at the sprint task.

**Rules:** no hard-coded thresholds (use `config/`), no PII in graders, no
fabricated metrics — numbers come from `evaluation/` only. Messidor-2 is used
for external validation only.

## 6. MATLAB / toolbox requirements

| Need | Requirement |
|---|---|
| Base runtime | MATLAB R2018b+ (uses `functiontests`, `genpath`, string functions) |
| Mock fallback | Image Processing Toolbox (im2uint8, rgb2gray, adapthisteq, imadjust, imgaussfilt, imresize) |
| Sprint 2+ grading | Deep Learning Toolbox + a pretrained backbone (resnet50 / efficientnetb0) |
| Sprint 3 calibration | Statistics and Machine Learning Toolbox (fminsearch) |
| Sprint 5 UI | MATLAB App Designer (review UI also runs as a programmatic `uifigure` reference; see `ui/README.md`) |
| Sprint 6 simulation | Simulink + SimEvents |
| Stage 5 analysis | Computer Vision Toolbox, where used (`normxcorr2` template path)

**No MATLAB installed on this dev machine:** the MATLAB code is canonical; the
Python verifier mirrors the mock for CI. See §3. Toolbox-dependent functions
(`adapthisteq`, etc.) degrade gracefully in the mock by leaving the image
unchanged and recording the skipped op.

## 7. Norms & disclaimer

- This is **screening decision-support**, not a diagnosis and not a replacement
  for an ophthalmologist. Reports carry this disclaimer.
- No clinical performance is claimed until `evaluation/runValidation` reports
  real numbers from real experiments (referable SE >90% / SP >85% are targets,
  not results). See `AGENTS.md`.