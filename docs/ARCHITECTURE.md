# RetinaSense — Technical Architecture (SIH 2026 PS 26038)

_Design document. No implementation code. See `RetinaSense_PRD.docx` for requirements._

---

## 1. HIGH-LEVEL ARCHITECTURE

```
                        ┌────────────────────────────────────────────────────────────┐
                        │                   SINGLE INGESTION ENTRY                    │
                        │                  ingestImage(case)                          │
                        └────────────────────────────────────────────────────────────┘
                                          │  (JPG/PNG fundus)
                                          ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                              IMAGE QUALITY GATE  (preprocessing/)                     │
│   focus ─ illumination ─ FOV coverage ─ artifacts   →  good / borderline / ungradable  │
└───────────────────────────────────────────────────────────────────────────────────────┘
        │ Ungradable                                   │ Borderline            │ Good
        ▼                                              ▼                       ▼
┌────────────────────┐                    ┌───────────────────────┐         skip
│ recaptureFeedback()│                    │ enhanceImage()        │
│  reason + guide    │                    │  CLAHE + illum-norm   │
└────────────────────┘                    │  + denoise             │
        │ (exit early)                    └───────────────────────┘
        │                                        │  recheckQuality()
        ▼                                        ▼  (still ungradable → recapture)
                                          ┌──────▼──────┐
                                          │ PASSED GATE │
                                          └──────┬──────┘
                                                 ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                          RETINAL ANALYSIS  (analysis/ — ADVISORY, non-blocking)        │
│     vessels ─ optic disc / fovea ─ lesion candidates  (evidence only, never blocks )   │
└───────────────────────────────────────────────────────────────────────────────────────┘
                                                 │ (evidence overlays, advisory)
                                                 ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                         DR SEVERITY GRADING  (classification/)                         │
│   ICDR grade 0–4  +  referable-DR probability (level 2+)                                │
│   backbone = benchmark-driven ResNet-50 vs EfficientNet-B0  (see §3.2)                 │
└───────────────────────────────────────────────────────────────────────────────────────┘
                                                 │
                                                 ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│              EXPLAINABILITY + CALIBRATION  (explainability/, calibration/)             │
│   Grad-CAM attention ─ calibrated confidence ─ uncertainty band                         │
└───────────────────────────────────────────────────────────────────────────────────────┘
                                                 │
                                                 ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                    REPORT + HUMAN REVIEW  (reporting/, ui/)                             │
│   annotated report ─ ophthalmologist approve/override/recapture ─ final referral        │
└───────────────────────────────────────────────────────────────────────────────────────┘

   PARALLEL (independent) deployment workflow:
┌───────────────────────────────────────────────────────────────────────────────────────┐
│   SIMULINK + SIMEVENTS DISTRICT-SCALE SIMULATION (simulink/)                            │
│   PHC arrivals → acquisition → bandwidth/transmission → AI processing → queue →        │
│   ophthalmologist review → bottleneck & annual-capacity analysis (100,000+ pax/yr)      │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

**Core principles:**
- The **quality gate is the entry gate**; its recapture feedback is a first-class differentiator.
- **Retinal analysis is advisory/evidence-only and never blocks grading** — this protects the working core (PRD §10, §13).
- The **classifier backbone is chosen by benchmark**, not pinned (see §3.2).
- The **Simulink model is an independent track** (its own folder) — the stated differentiator nobody else builds. As of freeze, the delivery is the parameter/scenario configuration (`simulink/scenario_params.m`) plus drivers that honestly raise `NotImplemented` until the `DRTelemedicine.slx` model is constructed (Sprint 6).

---

## 2. DETAILED PIPELINE

### Stage 0 — Ingestion
| Aspect | Detail |
|---|---|
| Input | Fundus image (JPG/PNG, RGB), patient metadata (id, eye, timestamp, phcId) |
| Processing | Validate decode; downscale to working size (max ~1024px, aspect preserved) for speed |
| Output | `working` image, `meta` struct |
| Toolbox | Image Processing (imread, imresize) |

### Stage 1 — Image Quality Assessment (IQA)
| Input | working RGB image |
|---|---|
| Processing | Classical CV metrics: **focus** (variance of Laplacian / Tenengrad energy, green channel), **illumination** (luminance mean/percentiles), **FOV coverage** (non-dark fraction vs circular FOV mask), **artifacts** (glare/saturation/clipping fraction). Combine via weighted rule-based scorer. |
| Output | `quality` struct: `score`, class `{good,borderline,ungradable}`, per-metric `failureReasons` |
| Toolbox | Image Processing (rgb2gray, conv2/Laplacian, morphology for FOV mask) |
| Metric | agreement with human-rated quality on small labeled subset; false-rejection rate |

### Stage 2 — Recapture Feedback
| Input | ungradable decision + failure vector |
|---|---|
| Processing | Map failing metric → reason code + actionable instruction |
| Output | `reasonCode`, `instruction`; exit pipeline |
| Metric | instruction applicability in field demo |

### Stage 3 — Adaptive Enhancement (borderline only)
| Input | borderline working image |
|---|---|
| Processing | CLAHE (`adapthisteq`) + illumination normalization + denoising, parameterized per failure metric |
| Output | `enhanced` image, `enhancement` metadata (which ops applied, params) |
| Toolbox | Image Processing (adapthisteq, imgaussfilt, medfilt2, imguidedfilter) |
| Metric | enhanced re-score improves; no harm on borderline validation subset |

### Stage 4 — Quality Re-check
| Input | enhanced image |
|---|---|
| Processing | Re-run Stage 1 scorer |
| Output | still ungradable → recapture; else proceed, flag `enhanced=true` |
| Metric | fraction of borderline that become gradable |

### Stage 5 — Retinal Structure / Lesion Analysis (advisory)
| Input | quality-passed image, FOV mask |
|---|---|
| Processing | **Vessels** (classical matched filter + morphology, optional U-Net on DRIVE); **optic disc** (bright temporal-side region / morphology / template fallback); **fovea** (dark region ≈1.5 disc-diam temporal of disc); **lesion candidates** (exudates = bright via top-hat+threshold; hemorrhages = dark-blob; MA = small round blobs). |
| Output | `evidence`: `vesselMask`, `opticDisc`, `fovea`, per-class `lesionMaps`, lesion counts/features |
| Toolbox | Computer Vision (templates/geo), Image Processing (morphology, top-hat, CC), DL-optional (U-Net) |
| Metric | Dice/overlap vs DRIVE & IDRiD where labeled; detection precision/recall; **never blocks grading** |

### Stage 6 — DR Severity Grading
| Input | quality-passed image (normalized to classifier input size) |
|---|---|
| Processing | **Transfer-learning CNN**, backbone = **benchmark-driven ResNet-50 vs EfficientNet-B0** (see §3.2; final backbone not pinned), planned fine-tune on APTOS 2019, 5-class head over ICDR 0–4; referable = level ≥ 2 |
| Output | `grading`: `rawProbs` (1×5), `grade` (0–4), `referableProb`, `referable` (bool) |
| Toolbox | Deep Learning (resnet50 / efficientnetb0, trainNetwork), IP |
| Model | Standard transfer-learning CNN — do NOT invent a novel architecture |
| Metric | Multiclass acc, weighted-kappa; **primary target** referable SE >90% / SP >85% on test + Messidor-2 external |

### Stage 7 — Explainability
| Input | quality-passed image, classifier, lesion evidence |
|---|---|
| Processing | Grad-CAM on referable/non-referable decision class → attention heatmap; separately overlay lesion evidence (never conflate attention with evidence) |
| Output | `explain`: `gradCam` heatmap, `evidenceOverlay`, `attentionImage` |
| Toolbox | Deep Learning (Grad-CAM), IP (imfuse, colormap) |
| Model | Grad-CAM — stated as attention, not causality (PRD §8) |
| Metric | reviewer qualitative rating; attention↔evidence coincidence (advisory) |

### Stage 8 — Calibration & Uncertainty
| Input | raw 5-class probs + validation logits |
|---|---|
| Processing | **Temperature scaling** fit on validation logits → calibrated probs; **uncertainty** = normalized entropy of calibrated distribution; threshold → `reviewRequired` routing |
| Output | `calibrated` struct: `calibratedProbs`, `confidence`, `uncertainty`, `reviewRequired` |
| Toolbox | Statistics & ML (temperature fit via fminsearch, entropy, ECE) |
| Model | Temperature scaling — standard, minimal, reliable |
| Metric | ECE, reliability diagram; confidence correlates with correctness |

### Stage 9 — Report + Human Review + Referral Decision
| Input | all accumulated Case fields |
|---|---|
| Processing | Compose structured report data; render annotated report; present to ophthalmologist via UI review; record approve/override/recapture |
| Output | `review` struct (status, decision) + final report file |
| Toolbox | App Designer UI, report rendering |
| Metric | time-to-review <30s; override rate |

### Stage 10 — Validation / Evaluation
| Input | test predictions + labels + calibrated probs |
|---|---|
| Processing | Confusion matrix, ROC/AUC, SE/SP (referable), ECE, kappa, per-level, **ablation** (quality gate, calibration, evidence, backbone) |
| Output | metrics tables, plots, saved artifacts |
| Toolbox | Statistics & ML (confusionchart, roc, perfcurve) |
| Metric | honest reported values; fixed seed/config reproducibility |

---

## 3. AI ARCHITECTURE (per decision, with rationale)

### 3.1 Image Quality Assessment — Classical CV + rule scoring (not DL)
No public labeled fundus-quality dataset at scale; gate must be deterministic, fast, explainable for recapture. Four hand-explainable metrics satisfy FR-02/FR-03. A trained model adds risk with no useful differentiation.

### 3.2 DR Classification — Transfer-learning CNN, backbone benchmark-driven
Candidates: **ResNet-50** and **EfficientNet-B0**, ImageNet-pretrained, fine-tuned on APTOS 2019. **Final model not pinned.** Selection by comparison on validation (or appropriate development set), deciding on:
- referable-DR **sensitivity** / **specificity** (primary target >90% / >85%)
- **AUROC** (referable and multiclass)
- **inference latency** (prototype hardware, PRD §13 speed constraint)
- **model size** (memory/storage for rural deployment)

A small benchmark harness (`scripts/benchmark_backbones.m`) trains both, reports the four-axis table, and `config/experiment_config.m` records the chosen backbone + its metrics. Prefer the one meeting clinical targets with acceptable latency; if both meet targets, take the cheaper/faster one. This is honest, reproducible backbone selection.

### 3.3 Vessel Segmentation — Classical matched-filter first; U-Net optional
DRIVE gives clean but small supervision; classical matched-filter yields decent vessels with zero training risk. Ship classical; add small U-Net if time permits and ablate. Advisory only.

### 3.4 Lesion Detection — Classical high-recall candidate detection, evidence-only
IDRiD has only a few dozen pixel-annotated images — too thin for robust sub-pixel MA/neovascularization segmenters. Classical high-recall candidates (bright exudates, dark hemorrhages, small round MA) give *evidence*, high-recall/low-precision posture. **Sub-pixel MA detection must not be claimed as achieved without evidence** (PS). Advisory, separated from classifier output.

### 3.5 Optic Disc / Fovea Localization — Classical CV (morphology + geometry + template fallback)
Deterministic, no training data, fast. Fovea derived geometrically from disc (≈1.5 disc-diam temporal). Advisory.

### 3.6 Explainability — Grad-CAM (standard)
Required by PS/PRD; well-supported in DL Toolbox. Presented strictly as model attention, not causality; combined with *separate* lesion evidence overlays.

### 3.7 Calibration — Temperature scaling
Single-parameter, robust, standard, needs only validation logits. Gives honest confidence + ECE; rejects softmax-as-certainty (FR-08).

### 3.8 Uncertainty — Normalized entropy of calibrated distribution + max-prob routing
Minimal, interpretable, no Bayesian machinery. Drives low-confidence → mandatory human review. Advanced uncertainty = IF-TIME.

---

## 4. MODULE INTERFACE CONTRACTS (deterministic I/O)

Central convention: every module consumes and emits a shared `Case` struct flowing through `runPipeline`.

```
runPipeline(case) → case        % orchestrator wires stages in order
```

### 4.1 Image Quality Assessment → score, class, failure reasons
```
quality = assessQuality(working, params)
quality.score       double 0..1
quality.class       ∈ {good, borderline, ungradable}
quality.metrics     struct: focus, illumination, fovCoverage, artifacts (each double 0..1)
quality.failureReasons cellstr, e.g. {'focus','illumination'}   % why not good, empty if good
quality.recapture   struct: reasonCode (string), instruction (string)  % set if ungradable
```

### 4.2 Enhancement → enhanced image + enhancement metadata
```
[enhanced, enhMeta] = enhanceImage(borderlineImage, quality, params)
enhanced   HxWx3 uint8
enhMeta    struct: appliedOps {clahe,illumNorm,denoise}, paramsPerOp, improved (bool), recheckClass
```

### 4.3 Retinal / Lesion Analysis → segmentation masks + quantitative lesion features
```
evidence = analyzeRetina(image, fovMask, params)
evidence.vesselMask       logical
evidence.opticDisc        [x,y]
evidence.fovea            [x,y]
evidence.lesions.<class>  struct per class (exudates, hemorrhages, microaneurysms, neoVasc):
                            .map     logical        % candidate map
                            .count   double
                            .features double×N      % area, roundness, intensity contrast, distanceToFovea
evidence.confidence       ∈ {low, medium, high}    % advisory confidence in detections
```

### 4.4 DR Grading → 5-class probabilities + referable DR probability
```
grading = classifyImage(image, net, params)
grading.rawProbs    1×5 double    % P(grade 0..4), row sums to 1
grading.grade        0..4         % argmax
grading.referableProb double 0..1 % P(grade ≥ 2) = rawProbs(3)+rawProbs(4)+rawProbs(5)
grading.referable   logical        % grade ≥ referThreshold (config, currently 2);
                                   % category-level rule matching clinical referral practice,
                                   % with referableProb reported alongside for calibration
```

### 4.5 Explainability → Grad-CAM heatmap + lesion evidence
```
explain = explainDecision(image, net, grading, evidence, params)
explain.gradCam        HxWx1 double  % normalized attention heatmap (model attention)
explain.attentionImage HxWx3 uint8   % overlay for display
explain.evidenceOverlay HxWx3 uint8  % lesion candidates overlaid (independent evidence)
explain.note           string        % "Model attention — not proof of causality"
```

### 4.6 Calibration → calibrated confidence + uncertainty
```
cal = calibrateOutput(grading, T, params)
cal.calibratedProbs  1×5 double      % temperature-scaled, sums to 1
cal.confidence       double 0..1     % max(calibratedProbs)
cal.uncertainty      double 0..1     % normalized entropy of calibratedProbs
cal.reviewRequired   logical         % true if confidence<thresh or uncertainty>thresh or forced
```

### 4.7 Human Review → approve / override / recapture / referral decision
```
review = submitReview(case, reviewerInput, params)
reviewerInput  struct: action ∈ {approve, override, recapture}, graderId, overrideGrade(0..4|[]), notes
review.action        ∈ {approve, override, recapture}
review.graderId      string
review.overrideGrade 0..4 | NaN
review.finalReferral logical       % final binary referral decision
review.status        ∈ {auto, approved, overridden, recapture, reqReview}
                     % reqReview: AI signal routed to review queue pending an
                     % ophthalmologist (set by runPipeline when review is
                     % required and no reviewer input is present at run time)
review.notes         string
```

### 4.8 Report Generator → structured report data + final PDF/report
```
report = buildReport(case, params)
report.data     struct (structured, machine-readable subset of case)
report.summary  string  % concise paragraph for rapid review
report.filepath string  % rendered PDF/PNG path
report.review   struct  % embedded final review/decision
```

All contract fields are mandatory (or explicitly `[]`/`NaN`) so integration is deterministic and unit-testable.

---

## 5. SOFTWARE ARCHITECTURE (repo for parallel work)

```
RetinaSense/
├─ README.md
├─ AGENTS.md                     # team conventions + commands (lint/test)
├─ config/
│  ├─ paths.m                    # data/model/output root config
│  └─ experiment_config.m        # seeds, thresholds, chosen backbone + benchmark metrics
├─ data/
│  ├─ raw/       (gitignored)    # APTOS, IDRiD, DRIVE, Messidor-2
│  ├─ processed/ (gitignored)    # resized/ready tensors
│  └─ manifests/                 # folds.csv, train/val/test + external split (committed)
├─ preprocessing/                # Stage 0-4: ingest + quality + recapture + enhancement
│  ├─ ingestImage.m
│  ├─ assessQuality.m
│  ├─ recaptureFeedback.m
│  ├─ enhanceImage.m
│  └─ recheckQuality.m
├─ analysis/                     # Stage 5 advisory (non-blocking)
│  ├─ segmentVessels.m
│  ├─ locateOpticDisc.m
│  ├─ locateFovea.m
│  ├─ detectLesions.m
│  └─ buildEvidence.m
├─ classification/               # Stage 6
│  ├─ prepareClassifierData.m
│  ├─ trainClassifier.m
│  ├─ evaluateClassifier.m
│  └─ classifyImage.m
├─ explainability/               # Stage 7
│  └─ computeGradCAM.m
├─ calibration/                  # Stage 8
│  ├─ fitTemperature.m
│  └─ applyCalibration.m
├─ reporting/                    # Stage 9
│  ├─ buildReport.m
│  └─ renderReport.m
├─ ui/                           # Stage 9 review UI (programmatic uifigure reference;
│  │                             #   App Designer .mlapp packaging is a planned follow-up)
│  └─ RetinaSenseApp.m
├─ evaluation/                   # Stage 10
│  ├─ runValidation.m
│  ├─ runAblation.m
│  └─ metrics.m
├─ simulink/                     # independent track
│  ├─ DRTelemedicine.slx
│  ├─ run_simulink_scenarios.m
│  ├─ analyze_capacity.m
│  └─ scenario_params.m
├─ scripts/
│  ├─ runPipeline.m              # main entry (CLI)
│  ├─ benchmark_backbones.m      # ResNet-50 vs EfficientNet-B0 selection harness
│  └─ run_all_experiments.m
├─ tests/
│  ├─ unit/
│  └─ integration/
├─ assets/                       # demo images (gitignored if large)
└─ docs/
   ├─ RetinaSense_PRD.docx
   └─ ARCHITECTURE.md            # this document
```

**Ownership units** (each folder = one owner, one stable contract via §4):
`preprocessing/`, `classification/`, `explainability/`, `calibration/`, `analysis/`, `reporting/+ui/`, `evaluation/`, `simulink/`. Members develop independently against the `Case` contract.

---

## 6. MATLAB ARCHITECTURE (logical separation)

| Logical unit | Folder | Responsibility |
|---|---|---|
| preprocessing | `preprocessing/` | ingest, quality, recapture, enhancement, recheck |
| quality assessment | `preprocessing/` | scorer + gate + recapture |
| enhancement | `preprocessing/` | CLAHE/illum/denoise + recheck |
| segmentation | `analysis/` | vessels, disc, fovea, lesions (advisory) |
| classification | `classification/` | transfer CNN train/infer |
| explainability | `explainability/` | Grad-CAM + evidence overlay |
| calibration | `calibration/` | temperature scaling + uncertainty |
| reporting | `reporting/` + `ui/` | report compose/render + review |
| evaluation | `evaluation/` | metrics, ablation, validation |
| UI | `ui/` | App Designer demo + human review |

---

## 7. SIMULINK ARCHITECTURE (SimEvents discrete-event model)

**Model: `simulink/DRTelemedicine.slx`** *(planned artifact — not yet in the repository; the folder ships configuration + drivers that raise `NotImplemented` until the model is built, see `simulink/README.md`)*

```
[Patient Arrival Generator] → [Acquisition Server] → [Transmission/Network Server]
   (Poisson/exponential)         (capture service)      (rate ∝ bandwidth/image size)
        │                                                  │
        ▼                                                  ▼
 [Recapture loop ◄── recaptureRate]   [Queue (FIFO)] → [AI Processing Server]
                                                          │
                                                          ▼
                                                  [Review Server × N reviewers]
                                                      (referralRate → review queue,
                                                       reviewTime, number of reviewers)
                                                          │
                                                          ▼
                                      [Throughput / Wait / QueueLen / Utilization sinks]
```

**Named inputs (workspace struct / Simulink params):** patient arrival rate, acquisition time, image size (MB), bandwidth (Mbps), transmission delay, AI processing time, recapture rate, referral rate, review time, number of reviewers.

**Outputs:** throughput (patients/day), mean/max wait, queue length, reviewer utilization, required bandwidth, bottleneck node, annual capacity.

**Driver `run_simulink_scenarios.m`:** what-if scenarios (low/high load; 1/2/4 Mbps rural bandwidth; 1/2/5 reviewers), tabulate, and **check whether 100,000 patients/yr (≈274/day) is achievable** per scenario. `analyze_capacity.m` finds bottleneck and recomputes resources. The annual-capacity claim is **only made after the model demonstrates it**.

---

## 8. MODEL / DATA INTERFACES + NAMING

**Models** under `data/models/`:
- `{backbone}_dr_aptos.mat` — trained net, e.g. `resnet50_dr_aptos.mat` / `efficientnetb0_dr_aptos.mat`
- `{backbone}_calib.mat` — fitted temperature T
- `{backbone}_metrics.mat` — hold-out + benchmark metrics

**Data** (manifests): `folds.csv`, `train.csv`, `val.csv`, `test.csv`; columns `image, eye_id, grade(0–4), split, source`. `image` is an absolute, repo-relative, or dataset-image-root-relative path; resolution is config-driven (`config/paths.m → data.images`, the primary fundus image root) and never depends on the working directory. **Messidor-2 kept out of train/val/hyperparams; touched only by external validation** (PRD §7).

**Augmentation** in `prepareClassifierData.m` (flip/rotate/scale/color-jitter), fixed seed, class weights / focal loss for imbalance.

---

## 9. ERROR / FALLBACK HANDLING

| Failure | Behavior |
|---|---|
| Image ungradable | Stop after gate → recaptureFeedback; no grading attempted |
| Enhancement fails | Route to recapture; never feed degraded image to grader |
| Lesion detection uncertain | Advisory high-recall mode; low/empty detections → `evidence.confidence=low`, grade unchanged; never blocks grading |
| Classifier confidence low | `reviewRequired=true` → mandatory human review (FR-08) |
| Model file missing | Caught at startup; clear error + setup message; refuse rather than default silently |
| Network unavailable | Prototype runs offline-batch; network is only a Simulink input, not a runtime dependency |
| No trained model | Training/benchmark scripts generate `.mat`; `runPipeline` validates presence and errors clearly |

---

## 10. SECURITY / PRIVACY (prototype-realistic only)

- Patient id as opaque token in `meta`; no PII beyond eye/eye-side in graders.
- Local filesystem only; no network transport in prototype runtime.
- `.gitignore` excludes `data/raw`, `data/processed`, model weights, demo datasets (biomedical licensing: IDRiD, Messidor-2 require access agreements).
- Report carries explicit "screening decision-support, not a diagnosis / not a replacement for an ophthalmologist" disclaimer.
- No secrets in repo; config holds paths only.

---

## 11. MVP PRIORITY

**MUST HAVE** (protect the working core):
- Quality gate + recapture feedback (`preprocessing/`)
- DR classifier, benchmark-driven backbone (`classification/`, `benchmark_backbones.m`)
- Grad-CAM (`explainability/`)
- Calibrated confidence + low-confidence routing (`calibration/`)
- Report + review UI + human-in-loop (`reporting/`, `ui/`)
- Basic Simulink district-capacity model + 100k/yr check (`simulink/`)
- Rigorous validation + external Messidor-2 (`evaluation/`)

**SHOULD HAVE:**
- Lesion detection as evidence (`analysis/detectLesions.m`)
- Vessel segmentation (`analysis/segmentVessels.m`)
- Optic disc / fovea localization (`analysis/`)

**IF TIME PERMITS:**
- Advanced lesion segmentation / neovascularization
- Advanced uncertainty analysis
- Full U-Net vessel betterment + ablation

**Rule:** `analysis/` is non-blocking — grading, explainability, validation, Simulink always ship first.

---

## 12. DEVELOPMENT ORDER (fastest path to working demo)

1. **Sprint 0 — Skeleton/data:** repo structure, `Case` struct, `runPipeline`, data + manifests, test harness.
2. **Sprint 1 — Quality gate (differentiator):** assessQuality + recapture; demo good/borderline/ungradable.
3. **Sprint 2 — Classifier + backbone benchmark:** train ResNet-50 & EfficientNet-B0, benchmark on SE/SP/AUROC/latency/size, **select finalized backbone**.
4. **Sprint 3 — Calibration + uncertainty:** temperature scaling, ECE, reviewRequired routing.
5. **Sprint 4 — Grad-CAM explainability** + evidence overlay placeholder.
6. **Sprint 5 — Report + review UI (App Designer):** end-to-end human-in-loop demo.
7. **Sprint 6 — Simulink district model** (parallel track, independent owner): scenarios + 100k/yr + bottleneck.
8. **Sprint 7 — Advisory analysis (SHOULD):** vessels, disc/fovea, lesion evidence, non-blocking.
9. **Sprint 8 — Validation & ablation + external Messidor-2** + honest write-up.
10. **Sprint 9 — Polish:** demo flow, IF-TIME, README/AGENTS.

Parallelism: Simulink (6) and analysis (7) are independent of the grader/quality core; separate members can start immediately.

---

## 13. ARCHITECTURE DIAGRAMS

### Overall system — see §1.

### AI Pipeline
```
Image
 ├─(ingest+downscale)
 ├─[Quality scorer]── good/borderline ─►[Enhance? ─► recheck]
 │        │ ungradable                        │
 │        ▼                                  ▼
 │     recapture ◄────────────────────────────┘
 │
 ├─►[Vessel seg ─]────────── advisory
 ├─►[Disc/fovea ─]────────── advisory
 ├─►[Lesion cands]────────── advisory evidence
 ▼
[DR CNN (backbone benchmark-driven)]
   ── 5-class rawProbs ─►[Temperature calib] ─► grade 0–4 + referableProb(≥2)
                                             │
                    [Grad-CAM] ◄─────────────┤
                    [uncertainty=entropy] ── low/high ─► mandatory human review
                                             │
          [Report + evidence overlay + calibrated confidence] ◄─┘
```

### Explainability Pipeline
```
graded image ─► Grad-CAM (on referable class) ─► attention heatmap (model attention)
                     │
                     ▼
     imfuse(attention, evidenceOverlays) ─► annotated image
           (attention and evidence labeled separately)
                     │
                     ▼
  report + confidence + uncertainty ─► reviewer inspects <30s
```

### Human-in-the-loop Workflow
```
AI decision + evidence + calibrated confidence
        │ confidence high & not forced
        ▼
    autoRefer / autoClear
        │  \ (low confidence OR override OR recapture policy)
        ▼   ▼
   REVIEW QUEUE → Ophthalmologist (App UI)
        │ approve / override / recapture
        ▼
   Final referral decision recorded → report finalized
```

### Simulink Workflow — see §7.

### Repository / Module Architecture — see §5 (ownership units).

---

## FINAL RECOMMENDED ARCHITECTURE (what to build)

**Modules & status:**
| Module | Folder | Status |
|---|---|---|
| Ingestion + quality gate + recapture | `preprocessing/` | **MUST** |
| Adaptive enhancement + recheck | `preprocessing/` | **MUST** |
| DR grader (benchmark-driven backbone) | `classification/` | **MUST** |
| Backbone benchmark harness (ResNet-50 vs EfficientNet-B0) | `scripts/benchmark_backbones.m` | **MUST** (defines final model) |
| Calibration + uncertainty | `calibration/` | **MUST** |
| Grad-CAM explainability | `explainability/` | **MUST** |
| Report + review UI | `reporting/` + `ui/` | **MUST** |
| Validation + ablation + external | `evaluation/` | **MUST** |
| Simulink district model | `simulink/` | **MUST** |
| Lesion detection / vessels / disc-fovea | `analysis/` | **SHOULD** |
| Advanced lesions / neovascularization / advanced uncertainty | — | **IF TIME** |

**Backbone decision:** benchmark-driven between ResNet-50 and EfficientNet-B0; select on referable SE/SP, AUROC, inference latency, model size. Not pinned now.

**Interface contracts:** exactly as §4 — 8 explicit I/O contracts (IQA, Enhancement, Retinal/Lesion Analysis, DR Grading, Explainability, Calibration, Human Review, Report Generator) sharing the `Case` struct through `runPipeline`.

**Priority:** MUST = quality+recapture, classifier+benchmark, calibration, Grad-CAM, report+review, validation, Simulink. SHOULD = analysis evidence. IF-TIME = advanced.

**Development order:** §12 (quality gate → classifier+benchmark → calibration → Grad-CAM → report/UI, with Simulink and analysis in parallel) — protects a working core first.

**Non-negotiables:** quality gate is the entry differentiator; evidence is advisory & non-blocking; calibration prevents softmax-as-certainty; the 100k/yr claim can be made only once the Simulink model is actually built and the analysis modules pass a real benchmark — never assume it; no fabricated accuracy — all numbers from `evaluation/`; Messidor-2 only for external validation; backbone chosen by real benchmark, never assumed.
