# RetinaSense — Team Execution & Ownership Map

_Sprint-to-member mapping for 2-day parallel implementation._

**Source of truth:** [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) and [`RetinaSense_PRD.docx`](RetinaSense_PRD.docx).
This document does NOT change any architecture, contracts, folder structure, or module interfaces.

---

## Principles

1. The existing Sprint numbers describe **development tasks**, not chronological dependencies.
2. All 3 members work **in parallel** after the shared foundation is frozen.
3. Each member develops against the **shared `Case` struct** (`core/newCase.m`) and the **interface contracts** in `docs/ARCHITECTURE.md §4`.
4. Mocks/placeholders enable independent testing; real implementations swap in behind identical interfaces.

---

## Shared Foundation (all members, done)

The shared foundation is NOT a blocking dependency for members 2 or 3. It establishes the skeleton that all members develop against.

| Task | Owner | Status |
|------|-------|--------|
| Repo structure, `Case` struct, `core/` | All (freeze) | Done |
| `config/` — all thresholds/experiment config | All (freeze) | Done |
| `scripts/runPipeline.m` — orchestrator skeleton | All (freeze) | Done |
| `tests/` — unit + integration harness | All (freeze) | Done |
| `docs/ARCHITECTURE.md` — contracts §4 | All (freeze) | Done |
| `AGENTS.md` — conventions | All (freeze) | Done |

**After the foundation freeze:** each member touches ONLY their owned folders. `core/`, `config/`, `scripts/runPipeline.m`, `tests/` may receive test additions but NOT structural changes without group agreement.

---

## Member 1 — AI/ML Core

### Scope

Everything that trains, runs, calibrates, and validates the DR grading model.

### Owned Folders & Files

| Folder | Files | Status |
|--------|-------|--------|
| `preprocessing/` | `assessQuality.m`, `enhanceImage.m`, `ingestImage.m`, `recaptureFeedback.m`, `recheckQuality.m` | Real CV implementations exist; tune thresholds |
| `classification/` | `classifyImage.m`, `trainClassifier.m`, `evaluateClassifier.m`, `prepareClassifierData.m` | Mock → real CNN |
| `explainability/` | `computeGradCAM.m` | Stub → real Grad-CAM |
| `calibration/` | `fitTemperature.m`, `applyCalibration.m` | Math real; wire T fitting |
| `evaluation/` | `metrics.m`, `runValidation.m`, `runAblation.m` | Math real; wire full pipeline |
| `scripts/` | `benchmark_backbones.m` | Stub → real benchmark |
| `config/` | `classification_config.m` | Read-only after freeze (update only model selection result) |

### Sprint Mapping

| Existing Sprint | Deliverable | Key Files |
|-----------------|-------------|-----------|
| **Sprint 1** — Quality Gate | Calibrate IQA thresholds against labeled quality subset; report false-rejection rate | `preprocessing/assessQuality.m`, `config/quality_thresholds.m` |
| **Sprint 2** — Classifier + Backbone Benchmark | Train ResNet-50 & EfficientNet-B0 on APTOS; benchmark 4-axis table; select backbone | `classification/trainClassifier.m`, `scripts/benchmark_backbones.m` |
| **Sprint 3** — Calibration + Uncertainty | Fit temperature on validation logits; wire `fitTemperature`; ECE + reliability diagram | `calibration/fitTemperature.m`, `calibration/applyCalibration.m` |
| **Sprint 4** — Grad-CAM + Evidence Overlay | Real Grad-CAM on referable class; evidence overlay from `analysis/` outputs | `explainability/computeGradCAM.m` |
| **Sprint 8** (partial) — Validation + Ablation | Confusion matrix, ROC/AUC, SE/SP, kappa, ECE; ablation studies; Messidor-2 external | `evaluation/runValidation.m`, `evaluation/runAblation.m`, `evaluation/metrics.m` |

### Execution Order

```
Sprint 1 → Sprint 2 → Sprint 3 → Sprint 4 → Sprint 8 (validation/ablation)
```

### Independent Test / Demo

- **Unit tests** in `tests/unit/` — add tests for each real implementation replacing a mock
- **Integration test** — run `scripts/runPipeline.m` end-to-end with real model
- **Benchmark demo** — `benchmark_backbones.m` produces the 4-axis table; results go into `cfg.model.metrics`
- **Calibration demo** — `fitTemperature` + `applyCalibration` on validation set; report ECE
- **Grad-CAM demo** — `computeGradCAM` produces visible attention heatmap on sample images
- **Validation demo** — `runValidation` produces honest metrics tables; no fabricated numbers

### What Member 1 Should NOT Touch

- `analysis/` — advisory retinal analysis (Member 2's domain)
- `reporting/`, `ui/` — report + review UI (Member 2's domain)
- `simulink/` — district simulation (Member 3's domain)
- `ui/RetinaSenseApp.m` — review UI reference implementation (Member 2's domain); App Designer `.mlapp` packaging planned as follow-up

### Dependency on Other Members

- **Needs from Member 2:** None. All `Case` fields are defined in `core/newCase.m`. Member 1 implements `classification/`, `explainability/`, `calibration/`, `preprocessing/`, `evaluation/` which write directly to `Case` fields.
- **Needs from Member 3:** None.

---

## Member 2 — Retinal Analysis + Reporting/UI

### Scope

Advisory retinal analysis (non-blocking), report generation, ophthalmologist review UI.

### Owned Folders & Files

| Folder | Files | Status |
|--------|-------|--------|
| `analysis/` | `analyzeRetina.m`, `segmentVessels.m`, `locateOpticDisc.m`, `locateFovea.m`, `detectLesions.m`, `buildEvidence.m` | Honest stubs → real CV implementations |
| `reporting/` | `buildReport.m`, `renderReport.m`, `submitReview.m` | Working mock → professional PDF/PNG rendering |
| `ui/` | `RetinaSenseApp.m` (+ `launchRetinaSenseApp.m`) | Programmatic `uifigure` reference implementation (Sprint 5) — `.mlapp` App Designer packaging is a planned follow-up |

### Sprint Mapping

| Existing Sprint | Deliverable | Key Files |
|-----------------|-------------|-----------|
| **Sprint 5** — Report + Review UI | Professional annotated report (PDF/PNG); ophthalmologist review interface with approve/override/recapture (`ui/RetinaSenseApp.m`); `<30s` review target | `reporting/buildReport.m`, `reporting/renderReport.m`, `ui/RetinaSenseApp.m` |
| **Sprint 7** — Advisory Retinal Analysis | Classical matched-filter vessel segmentation; optic disc localization (morphology + template); fovea localization (geometric from disc); high-recall lesion candidate detection (exudates, hemorrhages, MA) | `analysis/segmentVessels.m`, `analysis/locateOpticDisc.m`, `analysis/locateFovea.m`, `analysis/detectLesions.m`, `analysis/buildEvidence.m` |

### Execution Order

```
Sprint 5 + Sprint 7 in parallel (no internal dependency between them)
```

### Independent Test / Demo (using mock upstream)

Member 2 can develop and test entirely with mock/placeholder upstream outputs:

- **For `analysis/`:** Feed any test fundus image directly into `analyzeRetina()`. The function takes `(image, fovMask, params)` and does not depend on pipeline output. Test with synthetic images from `assets/`.
- **For `reporting/`:** Construct a mock `Case` struct via `core/newCase()` and populate the fields manually (grade, quality, calibrated, etc.) to test `buildReport()` and `renderReport()`.
- **For `ui/`:** Build the App Designer interface consuming mock `Case` data. Display evidence overlay, attention image, calibrated confidence, and approve/override/recapture controls.

**Key test patterns:**
```matlab
% Test analysis independently:
img = imread(fullfile('assets','synthetic_fundus_demo.png'));
evidence = analyzeRetina(img, [], struct());
% Verify: evidence.vesselMask is logical HxW, evidence.lesions has all 4 classes

% Test report independently:
c = newCase();
c.quality.class = 'good'; c.grading.grade = 1; c.grading.referable = false;
c.calibrated.confidence = 0.92; c.calibrated.uncertainty = 0.1;
c.review = struct('action','auto','graderId','','overrideGrade',NaN,'finalReferral',false,'status','auto','notes','');
report = buildReport(c, experiment_config());
% Verify: report.summary contains patient info, report.data fields populated
```

### What Member 2 Should NOT Touch

- `preprocessing/` — quality gate (Member 1's domain)
- `classification/` — DR grading CNN (Member 1's domain)
- `explainability/` — Grad-CAM (Member 1's domain)
- `calibration/` — temperature scaling (Member 1's domain)
- `evaluation/` — validation metrics (Member 1's domain)
- `simulink/` — district simulation (Member 3's domain)
- `scripts/runPipeline.m` — orchestrator (shared; no changes without group agreement)

### Dependency on Other Members

- **Needs from Member 1:** None for independent development. `analysis/` operates on raw images, not pipeline output. `reporting/` and `ui/` consume `Case` fields that can be populated from mocks.
- **Needs from Member 3:** None.

### Integration Note

At integration time, `runPipeline.m` calls `analyzeRetina()` at Stage 5 and the report/UI at Stage 9. Since Member 2 implements the exact contracts in `§4.3` (analysis) and `§4.7`/`§4.8` (review/report), the pipeline wires them in with zero changes to `runPipeline.m`.

---

## Member 3 — Simulink District Model

### Scope

SimEvents discrete-event simulation of the district-scale telemedicine workflow.

### Owned Folders & Files

| Folders | Files | Status |
|---------|-------|--------|
| `simulink/` | `DRTelemedicine.slx`, `scenario_params.m`, `run_simulink_scenarios.m`, `analyze_capacity.m`, `smoke_DRTelemedicine.m`, `build_DRTelemedicine.m` | **Complete** — full SimEvents model checked in and runnable; results persisted to `simulink/output/*.json` |

> **Member 3 note (completed):** `DRTelemedicine.slx` is committed and executes.
> `smoke_DRTelemedicine()` enforces `completedPatients > 0`, and the 100k/yr
> verdict in `analyze_capacity` is made from measured full-workday simulation,
> never an assumption. See `simulink/README.md` and `docs/AUDIT.md`.

### Sprint Mapping

| Existing Sprint | Deliverable | Key Files |
|-----------------|-------------|-----------|
| **Sprint 6** — Simulink District Model | SimEvents model: PHC arrivals → acquisition → bandwidth/transmission → AI processing → queue → ophthalmologist review → bottleneck analysis. What-if scenarios (low/high load, 1/2/4 Mbps, 1/2/5 reviewers). 100,000 patients/yr (≈274/day) achievability check. | `simulink/DRTelemedicine.slx`, `simulink/run_simulink_scenarios.m`, `simulink/analyze_capacity.m`, `simulink/scenario_params.m` |

### Execution Order

```
Sprint 6 (standalone, no dependency on AI pipeline)
```

### Independent Test / Demo

Member 3 can start immediately with no dependency on any other member:

- **`scenario_params.m`** — already complete; defines all named inputs (architecture §7)
- **`DRTelemedicine.slx`** — build SimEvents model using the architecture §7 block diagram:
  ```
  [Patient Arrival Generator] → [Acquisition Server] → [Transmission/Network Server]
      → [Queue (FIFO)] → [AI Processing Server] → [Review Server × N]
      → [Throughput / Wait / QueueLen / Utilization sinks]
  ```
- **`run_simulink_scenarios.m`** — drive what-if scenarios; tabulate throughput/wait/queue/utilization
- **`analyze_capacity.m`** — find bottleneck; recompute required resources for 274 patients/day

**Configurable parameters (from architecture §7):**
| Parameter | Default (scenario_params.m) | Notes |
|-----------|---------------------------|-------|
| Patient arrival rate | Poisson, ~274/day over 8h | `meanArrivalTimeMin = 1.75` |
| Acquisition time | 3.0 min | Capture service |
| Image size | 8.0 MB | Per OPD image |
| Bandwidth | 2.0 Mbps | Rural link; test 1/2/4 |
| Transmission delay | 15s fixed + rate-dependent | |
| AI processing time | 1.5 min | **Use configurable value, not actual model timing** |
| Recapture rate | 10% | Images sent back |
| Referral rate | 8% | Going to ophthalmologist |
| Review time | 5.0 min | Per review |
| Reviewer count | 2 | Test 1/2/5 |

**Key test:**
```matlab
smoke_DRTelemedicine();      % load/compile/smoke-run; FAILS if completedPatients <= 0
run_simulink_scenarios();    % produce scenario table + persist simulink/output/*.json
analyze_capacity();          % report measured bottleneck + required resources
% Check: 100,000 patients/yr achievable in at least one scenario (measured)
```
The 100k/yr check must be answered from **measured full-workday** simulation
output only — see `simulink/README.md` for the results recorded so far.

### What Member 3 Should NOT Touch

- `preprocessing/` — quality gate (Member 1's domain)
- `classification/` — DR grading CNN (Member 1's domain)
- `explainability/` — Grad-CAM (Member 1's domain)
- `calibration/` — temperature scaling (Member 1's domain)
- `evaluation/` — validation metrics (Member 1's domain)
- `analysis/` — retinal analysis (Member 2's domain)
- `reporting/`, `ui/` — report + review UI (Member 2's domain)
- `scripts/runPipeline.m` — orchestrator (shared; no changes without group agreement)

### Dependency on Other Members

- **Needs from Member 1:** None. The AI processing time is a **configurable parameter** in `scenario_params.m` (architecture §7). Member 3 does not need the actual trained model — only the service time estimate. Update `aiProcessTimeMin` in `scenario_params.m` once Member 1 benchmarks inference latency.
- **Needs from Member 2:** None.

---

## Parallel Execution Timeline

```
         Hour 0-2          Hour 2-8          Hour 8-16
         ┌──────────┐      ┌──────────────┐  ┌──────────────┐
Member 1:│ Foundation│─────▶│ Sprint 1+2   │─▶│ Sprint 3+4   │──▶ Sprint 8 (validation)
         │ (freeze)  │      │ quality+train │  │ calib+GradCAM│
         └──────────┘      └──────────────┘  └──────────────┘

         Hour 0-2          Hour 2-8          Hour 8-16
         ┌──────────┐      ┌──────────────┐  ┌──────────────┐
Member 2:│ Foundation│─────▶│ Sprint 5     │─▶│ Sprint 7     │──▶ Integration
         │ (read)    │      │ report+UI    │  │ analysis     │
         └──────────┘      └──────────────┘  └──────────────┘

         Hour 0-2          Hour 2-12         Hour 12-16
         ┌──────────┐      ┌──────────────┐  ┌──────────────┐
Member 3:│ Foundation│─────▶│ Sprint 6     │─▶│ Scenarios +  │──▶ Integration
         │ (read)    │      │ build model  │  │ bottleneck   │
         └──────────┘      └──────────────┘  └──────────────┘
```

**Sprint 8/9 — Integration & Polish (all members):**
- Member 1: Final validation + ablation + Messidor-2 external; honest metrics write-up
- Member 2: Wire analysis into pipeline evidence overlay in report; polish UI
- Member 3: Update `aiProcessTimeMin` from Member 1's latency benchmark; final scenario run

---

## Integration Points (end of Day 2)

| Integration | What Connects | Owner | Touches |
|-------------|---------------|-------|---------|
| Pipeline wire-up | `runPipeline.m` already calls all §4 contracts | Shared | No changes needed if contracts are followed |
| Evidence overlay in report | `computeGradCAM` reads `c.evidence` from `analyzeRetina` | Member 1 reads Member 2's output | `Case.evidence` field (already defined in `newCase.m`) |
| Report renders real outputs | `buildReport` reads `c.grading`, `c.calibrated`, `c.explain`, `c.evidence` | Member 2 reads Member 1's output | `Case` fields (already defined) |
| Simulink latency update | `scenario_params.m` → `aiProcessTimeMin` from benchmark | Member 3 reads Member 1's result | One parameter in `scenario_params.m` |
| Tests pass | `runtests('tests')` | All members add tests | `tests/unit/` and `tests/integration/` |

---

## Shared Files (read-only for members, changes by agreement only)

| File | Purpose | Who May Edit |
|------|---------|-------------|
| `core/newCase.m` | Case schema — the shared data contract | All (add fields only, never remove) |
| `core/raiseError.m` | Error signaling | Read-only |
| `core/logMessage.m` | Logging | Read-only |
| `config/experiment_config.m` | Central config | Member 1 (model selection); others read-only |
| `config/quality_thresholds.m` | Quality gate thresholds | Member 1 (Sprint 1 tuning) |
| `config/preprocess_config.m` | Preprocessing params | Member 1 |
| `config/classification_config.m` | Classification params | Member 1 |
| `scripts/runPipeline.m` | Orchestrator | Shared by agreement |
| `AGENTS.md` | Team conventions | Shared by agreement |

---

## Rules of Engagement

1. **No member waits for another.** Use mocks/placeholders for independent testing.
2. **Contracts are frozen.** `docs/ARCHITECTURE.md §4` is the single source of truth for module I/O.
3. **No fabricated metrics.** Numbers come from `evaluation/` and real experiments only.
4. **Analysis is non-blocking.** `analysis/` failure never changes grading/referral behavior.
5. **Messidor-2 is external-only.** Never in train/val splits.
6. **Config-driven thresholds.** No magic numbers in module code.
7. **Honest placeholders.** Placeholder modules return empty/zero outputs with notes — never fake data.
8. **TODO markers stay precise.** `TODO(Sprint N): <specific task>` — remove only when real implementation lands.
