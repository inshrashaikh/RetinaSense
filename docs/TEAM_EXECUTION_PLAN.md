# RetinaSense — Team Execution Plan (4 members)

_Sprint-to-member mapping for independent 2-day parallel implementation._

**Source of truth:** `docs/ARCHITECTURE.md` and `docs/RetinaSense_PRD.docx`. This
document ONLY reassigns ownership of existing work. It does NOT change the
pipeline flow, `Case` struct, §4 module contracts, folder structure, Simulink
architecture, quality-gate logic, advisory/non-blocking analysis rule,
calibration design, or explainability design.

---

## Principles

1. Sprint numbers are **development-task labels, not a global sequential
   dependency**:
   - Member 1 → **Sprint 1 + 2 + 3 + 4 + 8**
   - Member 2 → **Sprint 7**
   - Member 3 → **Sprint 6**
   - Member 4 → **Sprint 5**
   - **Sprint 9** = final polish/integration (all members).
   - Shared foundation/contract freeze (already done).
2. All 4 members work **in parallel** after the foundation freeze.
3. Each member develops against the shared `Case` struct (`core/newCase.m`) and
   §4 contracts. **Intra-implementation dependencies between members: NONE.**
4. Mocks/placeholders (`core/newCase.m` populated with realistic fields) enable
   independent testing; real implementations swap in behind identical interfaces.
5. Integration happens only at the end.

---

## 4-Member Ownership Overview

| Member | Workstream | Owned folders | Existing sprints |
|---|---|---|---|
| **Member 1** | AI/ML Core | `preprocessing/`, `classification/`, `explainability/`, `calibration/`, `evaluation/`, `scripts/benchmark_backbones.m` | 1, 2, 3, 4, 8 |
| **Member 2** | Retinal Analysis | `analysis/` | 7 |
| **Member 3** | Simulink District Model | `simulink/` | 6 |
| **Member 4** | Reporting + Review UI | `reporting/`, `ui/` | 5 |

Shared foundation (frozen, read-only unless agreed): `core/`, `config/`,
`scripts/runPipeline.m`, `scripts/run_all_experiments.m`, `scripts/demo_mock_pipeline.m`,
`tests/`.

---

## Member 1 — AI/ML Core (sprints 1, 2, 3, 4, 8)

**Responsibilities:** image ingestion, IQA, quality gate, borderline enhancement,
recapture logic, DR classification (Level 0–4), referable DR (Level ≥ 2),
ResNet-50 vs EfficientNet-B0 benchmark, Grad-CAM, calibration, confidence,
uncertainty, validation metrics, ablation, external Messidor-2 validation.

| Owned folder | Owned files |
|---|---|
| `preprocessing/` | `ingestImage.m`, `assessQuality.m`, `recaptureFeedback.m`, `enhanceImage.m`, `recheckQuality.m` |
| `classification/` | `prepareClassifierData.m`, `trainClassifier.m`, `evaluateClassifier.m`, `classifyImage.m` |
| `explainability/` | `computeGradCAM.m` |
| `calibration/` | `fitTemperature.m`, `applyCalibration.m` |
| `evaluation/` | `runValidation.m`, `runAblation.m`, `metrics.m` |
| `scripts/` | `benchmark_backbones.m` |
| `config/` | `quality_thresholds.m`, `preprocess_config.m`, `classification_config.m`, `experiment_config.m` (model-selection result only) |

**Independent test/demo:**

- `python tools/python_verifier/mock_pipeline.py` + `scripts/demo_mock_pipeline.m` smoke tests.
- Sprint 2: `benchmark_backbones.m` produces the 4-axis table (referable SE/SP,
  AUROC, latency, size); selected backbone + metrics recorded in
  `config/experiment_config.m`.
- Sprint 8: `evaluation/runValidation.m` / `runAblation.m` on test + Messidor-2
  external; **all numbers from real experiments, never fabricated.**
- Test against `core/newCase.m` mocks for `analysis/` (evidence `[]`) and
  `reporting/` outputs.

**Must NOT modify:** `analysis/`, `reporting/`, `ui/`, `simulink/`.

**Dependencies:** none. Evidence in `c.evidence` defaults to empty from mocks;
Grad-CAM/classification write only their own `Case` fields.

---

## Member 2 — Retinal Analysis (sprint 7)

**Responsibilities:** vessel segmentation, optic disc localization, fovea
localization, lesion candidate detection (microaneurysms, exudates,
hemorrhages, neovascularization if feasible), evidence masks/features, evidence
construction. **Advisory and non-blocking — never affects grading/referral.**

| Owned folder | Owned files |
|---|---|
| `analysis/` | `analyzeRetina.m`, `segmentVessels.m`, `locateOpticDisc.m`, `locateFovea.m`, `detectLesions.m`, `buildEvidence.m` |

**Independent test/demo:**

- `analyzeRetina(image, fovMask, params)` reads a fundus image directly —
  no pipeline dependency. Use `assets/` demo + synthetic images.
- Verify `evidence` matches §4.3 (logical `vesselMask`, `[x,y]` disc/fovea,
  4 lesion classes with `map`/`count`/`features`, `confidence` ∈ {low, medium, high}).
- Volume/edge cases return honest empty evidence + `confidence='low'`; never
  invented detections.

**Must NOT modify:** `preprocessing/`, `classification/`, `calibration/`,
`evaluation/`, `reporting/`, `ui/`, `simulink/`.

**Dependencies:** none. Works on raw images only.

---

## Member 3 — Simulink District Model (sprint 6)

**Responsibilities:** patient arrival, image acquisition, network transmission,
queue, AI processing server, ophthalmologist review, reviewer resources,
throughput, waiting time, queue length, utilization, bottleneck analysis,
1/2/4 Mbps scenarios, 1/2/5 reviewers, 100,000+ patients/yr feasibility.

| Owned folder | Owned files |
|---|---|
| `simulink/` | `DRTelemedicine.slx`, `scenario_params.m`, `run_simulink_scenarios.m`, `analyze_capacity.m` |

**Independent test/demo:**

- Build the §7 SimEvents model from `scenario_params.m` named inputs.
- `run_simulink_scenarios.m` tabulates throughput/wait/queue/utilization across
  scenarios; `analyze_capacity.m` reports bottleneck + required resources.
- Check 100,000 patients/yr (≈274/day) achievable in ≥1 scenario.
- **AI processing time is a CONFIGURABLE SIMULATION PARAMETER**
  (`aiProcessTimeMin` in `scenario_params.m`) — no trained model required.

**Must NOT modify:** `preprocessing/`, `classification/`, `analysis/`,
`reporting/`, `ui/`, `evaluation/`.

**Dependencies:** none. The only cross-member touch is Member 1's latency
benchmark feeding `aiProcessTimeMin` at final integration.

---

## Member 4 — Reporting + Review UI (sprint 5)

**Responsibilities:** professional annotated report, PDF/PNG report rendering,
ophthalmologist review interface, display of quality/DR result/confidence/
calibration fields, Grad-CAM + evidence placeholders, approve/override/recapture,
review notes, final referral/review status.

| Owned folder | Owned files |
|---|---|
| `reporting/` | `buildReport.m`, `renderReport.m`, `submitReview.m` |
| `ui/` | `RetinaSenseApp.mlapp` (build; currently only `ui/README.md`) |

**Independent test/demo:**

- Construct a **mock Case** via `core/newCase.m` and populate realistic fields
  (quality, grading, calibrated, explain, evidence, review) to exercise the full
  report render and the App UI without Member 1 or Member 2.

```matlab
c = newCase();
c.quality.class = 'good';
c.grading = struct('rawProbs',[.05 .1 .35 .3 .2], 'grade',2, ...
                   'referableProb',.85, 'referable',true, 'modelFile','mock');
c.calibrated = struct('calibratedProbs',[.05 .1 .35 .3 .2], ...
                      'confidence',.35, 'uncertainty',.6, 'reviewRequired',true);
c.explain.note = 'Mock placeholders only';
report = buildReport(c);        % → report.summary, report.filepath (PDF/PNG)
review = submitReview(c, struct('action','approve','graderId','g1', ...
                                'overrideGrade',NaN,'notes','ok')); % §4.7
```

- Render placeholders for Grad-CAM/evidence overlays when fields are empty
  (do not invent attention/detections).

**Must NOT modify:** `preprocessing/`, `classification/`, `analysis/`,
`calibration/`, `evaluation/`, `simulink/`.

**Dependencies:** none. Consumes only the frozen `Case` fields through the §4.7/§4.8
contracts.

---

## Final Integration Points (end of Day 2, Sprint 9)

| Integration | What connects | Participants |
|---|---|---|
| Pipeline wire-up | `scripts/runPipeline.m` already calls every §4 contract in order | Shared — no changes if contracts are honored |
| Evidence overlay | `explainability/computeGradCAM` reads `c.evidence` from `analysis/analyzeRetina` | Member 2 → Member 1 |
| Report renders real outputs | `reporting/buildReport` reads `c.grading`, `c.calibrated`, `c.explain`, `c.evidence`; UI shows them | Members 1+2 → Member 4 |
| Simulink latency param | `scenario_params.m → aiProcessTimeMin` from Member 1 latency benchmark | Member 1 → Member 3 |
| Validation write-up | `evaluation/` numbers reported in final demo + `README` | Member 1, all review |
| Full suite passes | `runtests('tests')` + `python tools/python_verifier/mock_pipeline.py` | All — each adds tests for owned modules |

All integration happens through the **frozen** `Case` fields in `core/newCase.m`
and the §4 contracts; no `runPipeline.m` structural change required.

---

## 2-Day Parallel Execution Timeline

```
        Shared foundation        Day 1                          Day 2
Member 1 [contract read] → S1 IQA → S2 classifier+benchmark → S3 calib → S4 Grad-CAM → S8 validate+ablate+Messidor-2
Member 2 [contract read] → S7 vessels/disc/fovea → S7 lesion candidates → evidence, synthetic+assets testing
Member 3 [contract read] → S6 build SimEvents model → scenarios 1/2/4 Mbps × 1/2/5 reviewers → bottleneck + 100k/yr check
Member 4 [contract read] → S5 buildReport/renderReport → RetinaSenseApp.mlapp review flow → mock-Case full render demo
        → Sprint 9: integration + runtests + polish (all members, final)
```

Shared read-only (change only by group agreement): `core/*`, `config/*`,
`scripts/runPipeline.m`, `AGENTS.md`, `docs/ARCHITECTURE.md`.