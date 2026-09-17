# RetinaSense Audit

Status: **open**. Findings below were raised and fixed in the 2026-09 sprint. This
file records each finding, its resolution, and the evidence/verification behind it.
Nothing here is a clinical claim; every metric mentioned comes from a real
`evaluation/`-style run (see guardrail #1) or is explicitly marked MOCK.

Scope reviewed: backend FastAPI + auth, enhancement-recheck grading path, clinical
PDF report, MATLAB analysis modules (guardrail #2 config hygiene), repo hygiene,
frontend test health, and the Simulink district-capacity track.

---

## Summary

| ID | Severity | Finding | State |
|----|----------|---------|-------|
| C1 | High | Hardcoded/insecure dev token secret fallback in auth | Fixed + verified |
| C2 | High | Auth/security code present but never committed (silent regression risk) | Fixed (commit hygiene) |
| C3 | Medium | Untracked runtime junk (`uvicorn*.log`) not ignored | Fixed (`.gitignore`) |
| C4 | High | Enhancement-recheck recapture returned a 500 / misleading "completed" | Fixed + tested |
| C5 | High | User-controlled fields not escaped in clinical PDF report (HTML/XML injection) | Fixed + tested |
| C6 | High | PDF report always 500'd on reportlab 5 (`styles["Small"]` removed) | Fixed + tested |
| C7 | Medium | Analysis modules hard-coded thresholds instead of reading config (guardrail #2) | Fixed |
| C8 | Medium | Frontend test asserted unique text that legitimately appears twice | Fixed |
| S1 | Medium | Simulink smoke passed even when the model produced zero entities | Fixed + verified |
| S2 | High | `build_DRTelemedicine` deleted the existing `.slx` unconditionally; paths used `pwd` | Fixed |
| S3 | Medium | Throughput print hard-coded a "274" fudge; partial windows were extrapolated to a day | Fixed |
| S4 | Medium | Real simulation results were never persisted | Fixed (JSON) |
| S5 | High | 100,000/yr capacity claim was unverified against measured simulation | Fixed + verified (measured) |
| R1 | Medium | Clinical PDF advertised a black zero-map mock as "attention" (over-claim, guardrail #3) | Fixed + tested |
| R2 | Medium | Quality-gate thresholds never calibrated against a labeled subset | PENDING (harness ready) |
| R3 | Medium | Borderline case reclassified 'good' after enhancement, contradicting the routing contract | Fixed + tested |
| S6 | Low | Simulink docs said "planned artifact / stubs" although the model is committed | Fixed |

Deferred / not yet actionable:

| ID | Item | Note |
|----|------|------|
| D1 | Experiment artifacts | `experiment_pipeline.py` full run deferred; existing artifacts are stale, must be regenerated before any metric claim |
| D2 | MATLAB execution | remaining `.m` edits (C-series) verified by review + Python-side tests only; run `runtests('tests')` on a MATLAB box to confirm |

---

## C1 — Token secret fail-closed (High) — FIXED

**Finding.** `backend/app/config.py` fell back to a known-insecure hard-coded
secret (`retinasense-dev-secret-do-not-use-in-prod`) whenever
`RETINASENSE_TOKEN_SECRET` was unset. A deployed instance with no env var would
silently run with a publicly-known signing key. `backend/tests/conftest.py` did
not pin a test secret, so tests exercised the insecure path.

**Fix.**
- `backend/app/config.py`: removed the hard-coded fallback. New behaviour:
  1. `RETINASENSE_TOKEN_SECRET` set to a real value → used as-is, `AUTH_FAIL_CLOSED=False`.
  2. `RETINASENSE_ALLOW_INSECURE_AUTH=1` → ephemeral `secrets.token_hex(32)`
     generated per process, `TOKEN_SECRET_INSECURE=True`, `AUTH_FAIL_CLOSED=False`
     (explicit opt-in for local/dev), with a startup warning.
  3. Otherwise → empty secret, `TOKEN_SECRET_INSECURE=True`, `AUTH_FAIL_CLOSED=True`.
- `backend/app/main.py`: `lifespan` raises `RuntimeError("AUTH_FAIL_CLOSED")` to
  refuse startup when no secret is configured; prints `logger.warning` when the
  insecure opt-in branch is active.
- `backend/app/utils/security.py`: docstring documents the three modes.
- `backend/tests/conftest.py`: sets `RETINASENSE_TOKEN_SECRET` before any app
  import so tests exercise the secure path deterministically.

**Verification.**
- Fresh process, no env → `config.AUTH_FAIL_CLOSED is True`.
- `RETINASENSE_ALLOW_INSECURE_AUTH=1` → `TOKEN_SECRET_INSECURE is True`, secret
  length 64, ephemeral.
- Backend suite: `49 passed`.

---

## C2/C3 — Uncommitted auth code + runtime junk (High/Medium) — FIXED

**Finding.** The whole auth implementation (`auth_deps.py`, `routes/auth.py`,
`services/auth.py`, `utils/security.py`) plus `services/explainability.py` and
`services/pdf_report.py` were untracked — not in any commit. `backend/uvicorn*.log`
were untracked runtime logs polluting `git status`.

**Fix.**
- Added `backend/uvicorn*.log` to `.gitignore`.
- Committed the backlog (auth + security + report code and the sweep of C1/C4/C5
  file changes) as one focused commit.

**Verification.** `git status --short` clean for the fixed set.

---

## C4 — Enhancement-recheck recapture path (High) — FIXED + TESTED

**Finding.** When the enhancement recheck concluded *still borderline* (or the
enhanced image degraded), the screening flow produced a completed result instead
of a recapture instruction — the API could even 500 because the returned struct
was incomplete, and the frontend only handles `recapture_required` for the
quality-gate exit.

**Fix.**
- `backend/app/services/matlab_adapter.py`: when the mapped quality has
  `recaptureReason` set (i.e. `quality.class == 'ungradable'` **or** an
  explicit recheck recapture reason), return early with quality metadata and no
  grading/evidence — no downstream stage runs on a ungradable image (guardrail #4).
- `backend/app/services/screening.py`: status becomes `recapture_required` when
  `quality_class == 'ungradable'` or `recaptureReason` is present; screening is
  persisted and the pipeline short-circuits.
- API contract: "no AI result" is an empty `AiPrediction` struct (all fields
  null), not JSON `null` — the frontend `hasPrediction()` guards on the null grade.

**Verification.** New `_RecheckRecaptureAdapter` + `test_recheck_recapture_state`
in `backend/tests/test_api.py` asserts: service-level status `recapture_required`,
`aiPrediction` empty, GET returns `recapture_required` with the borderline class,
`recaptureInstruction` preserved, and `aiPrediction.grade is None`. Backend:
`49 passed`.

---

## C5 — Unescaped user fields in PDF report (High) — FIXED + TESTED

**Finding.** `backend/app/services/pdf_report.py` interpolated patient/case text
into reportlab `Paragraph`/`Image` HTML-format strings without escaping. A
patient name containing `<`, `&`, etc. could corrupt the layout or inject markup.

**Fix.**
- `_render_html_field` now escapes both label and value via
  `xml.sax.saxutils.escape`.
- The quality section escapes `failureReasons` and `recaptureInstruction`, and
  only formats `:.0%` when the score is actually numeric (`isinstance(q_score,
  (int, float))`) so a non-numeric score can't crash the build.

**Verification.** New `backend/tests/test_pdf_report.py`:
`test_render_html_field_escapes_user_text`, plus hostile-field and non-numeric
score build tests that never crash. Backend: `49 passed`.

---

## C6 — PDF always failed on reportlab 5 (High) — FIXED + TESTED

**Finding.** While fixing C5, the report never built: reportlab 5.0.1 removed the
`"Small"` paragraph style from `getSampleStyleSheet()`, so `styles["Small"]`
raised a `KeyError` on every `/report` PDF request (pre-existing, independent of
C5).

**Fix.** `pdf_report.py` defines an explicit `small_style =
ParagraphStyle("RSSmall", parent=styles["BodyText"], fontSize=8.5, leading=11)`
and uses it at all three former `styles["Small"]` call sites (header, Grad-CAM
caption, disc detail).

**Verification.** All three PDF build tests in `test_pdf_report.py` complete and
produce bytes; full backend suite `49 passed`.

---

## C7 — Analysis modules hard-coded values (guardrail #2) (Medium) — FIXED

**Finding.** `analysis/locateOpticDisc.m`, `locateFovea.m`, `segmentVessels.m`,
`detectLesions.m` embedded raw thresholds/radii (e.g. `green > 0.05`,
`strel('disk', 15)`, `discRadius * 1.2`), violating AGENTS.md guardrail #2.

**Fix.** All values moved to `config/analysis_config.m` with **behavior-preserving
defaults** (identical to the previous constants):

- Shared FOV geometry: `fovThreshold` (0.05), `minFovFraction` (0.1),
  `illumDiskRadius` (15).
- `opticDisc`: new `morphology.cleanupOpenRadius`/`cleanupCloseRadius`,
  `template.minRadiusPx`/`maxRadiusFraction`.
- `vessels`: `numOrientations`, `filterSigmaMultiplier`, `minFilterSize`,
  `responsePercentile`, `minResponseSamples`, `minAreaPx`, `closeDiskRadius`.
- `fovea`: `fovThreshold`, `temporalRegionFraction`, `minSearchAreaPx`,
  `gaussSigma`, `darknessThreshold`.
- `lesions`: `discDefaultRadiusPx`, `discSuppressMultiplier`,
  `features.bgDiskRadius`, plus per-lesion `minArea`/`maxArea`,
  `topHatRadius`/`bottomHatRadius`, `vesselDilateRadius`,
  `cleanupOpenRadius`/`cleanupCloseRadius`, and neovascular
  `densityDiskRadius`/`densityPercentile`/`minDensitySamples`.
  `extractLesionFeatures` takes the dilation radius as an explicit argument.

Modules now `raiseError`-free of magic numbers and read every value from their
self-contained config sub-struct (contract unchanged — sub-struct or full config
both accepted by `analyzeRetina`).

**Verification.** MATLAB tests cannot run in this environment; defaults were kept
identical, and the module call signature/`Case` fields are unchanged. **D2**: run
`runtests('tests')` on a MATLAB box to confirm.

---

## C8 — Frontend test asserted non-unique text (Medium) — FIXED

**Finding.** `frontend/tests/cases.test.tsx` used `screen.findByText(/Moderate
NPDR/)` where "Moderate NPDR" legitimately appears twice (the AI prediction panel
row "2 · Moderate NPDR" and the badge "AI grade 2 (Moderate NPDR)"), making the
query ambiguous and the test fail.

**Fix.** Assert on multiplicity:
`expect((await screen.findAllByText(/Moderate NPDR/)).length).toBeGreaterThan(0);`

**Verification.** Frontend vitest suite passes (re-run after fix).

---

## D1 — Experiment artifacts (deferred)

`evaluation/`-style artifacts in `output/` and `data/models/` are stale relative
to the current code. No accuracy/SE/SP/ECE/kappa claim should be made from them.
Run `tools/python_verifier/experiment_pipeline.py` (full, both backbones) to
regenerate, then re-link `config/experiment_config.m` to the freshly chosen
backbone before making any metric claim.

---

## S1 — Simulink smoke did not fail on zero throughput (Medium) — FIXED + VERIFIED

**Finding.** `simulink/smoke_DRTelemedicine.m` claimed it verified "entities
flow: completedPatients > 0", but it only set `status.simRuns = true`; a model
that ran yet completed zero patients still reported a passing smoke.

**Fix.** The smoke now hard-fails when `completedPatients` is missing (NaN) or
`<= 0`, throwing `RetinaSense:smoke_DRTelemedicine:NoEntitiesFlow` (nonzero exit
for CI), and returns a single `status.ok` verdict. The model path is resolved
from the script's own folder (`simulink/`), not `pwd`.

**Verification.**
- `smoke_DRTelemedicine()` on the committed model (seed 42, 1h window):
  `loads=1 compiles=1 simRuns=1 entitiesFlow=1 completed=17 unresolved=0` → **PASS**.
- The `completedPatients <= 0` branch is unit-verifiable by replacing the sim
  sink count with a zero/NaN — the check throws as designed.

## S2 — `build_DRTelemedicine` overwrote the committed model blindly (High) — FIXED

**Finding.** `build_DRTelemedicine.m` did `delete(fullfile(pwd, [mdl '.slx']))`
unconditionally and saved via bare `save_system(mdl)` — a stray call (wrong
folder, default args) silently destroyed the checked-in `DRTelemedicine.slx`.

**Fix.**
- Path-robust: the model is loaded from and saved to the script's own directory
  (`fileparts(mfilename('fullpath'))`), independent of the current folder.
- Safe: an existing `<mdl>.slx` is **never** overwritten without an explicit
  third argument `build_DRTelemedicine('DRTelemedicine', false, true)`. Without
  it, the call errors with `RetinaSense:build_DRTelemedicine:WouldOverwrite`.

**Verification.** `build_DRTelemedicine()` against the committed model now
refuses to overwrite (error path exercised); the committed `.slx` is untouched.

## S3 — Hardcoded throughput in KPI print + partial-window extrapolation (Medium) — FIXED

**Finding.** `run_simulink_scenarios.m` printed the measured window as
`r.patientsPerDay / 274 * 8` (a hard-coded "274" scaling), and
`throughput = completedPatients` was reported even for a partial (e.g. 1h)
simulation window — implying a daily rate the model never produced.

**Fix.**
- The window is now recorded as `simTimeHours` + `measurementWindow`
  (`FULL_WORKDAY` / `PARTIAL_WINDOW`) on every result.
- `throughput`/`annualCapacity` are MEASURED **only** when the window is a full
  workday (8h); a partial window reports `NaN` and is never extrapolated.
- The KPI print shows the true window in hours, with no hard-coded divisor.

## S4 — Simulation results never persisted (Medium) — FIXED

**Finding.** Scenario runs printed tables but wrote no data; nothing survived
the session for the audit trail.

**Fix.** `run_simulink_scenarios` now writes
`simulink/output/district_capacity_results_<timestamp>.json` (git-ignored
runtime output), with MATLAB/Simulink/SimEvents versions and a per-field
MEASURED/ANALYTICAL data-source policy. `NaN`/`Inf` are never encoded as JSON
numbers (they become `null`).

**Verification.** A full scenario run produced the JSON file (see §S5).

## S5 — 100,000/yr capacity claim unverified (High) — FIXED + VERIFIED (MEASURED)

**Finding.** The repo claimed a district node "can serve ~100,000 patients/year
(~274/day)" with no measured simulation backing.

**Fix.** `analyze_capacity` now renders the feasibility verdict from **measured
full-workday** simulation outputs only, and the claim text in this file reflects
those results. `run_simulink_scenarios` persisted the measurement per scenario.

**Verification (MEASURED, seed 42, full 8h window).**
- Baseline (`274/day` configured arrival load; 2.0 Mbps; 2 reviewers):
  `completedPatients = 143` → measured throughput **143 patients/workday**,
  `143 × 365 ≈ 52,195 patients/year`.
- Therefore the **100,000/year target is NOT achieved** under the baseline
  single-camera configuration. The analytical bottleneck is **Acquisition**
  (single camera, 3.0 min + 10% recapture ⇒ ≈200 s effective service ⇒ ~144/day
  bound), consistent with the measured 143.
- `analyze_capacity`'s analytical what-if therefore flags the required change:
  **2 acquisition stations** (all other resources are sufficient at the target).
- Per-scenario measured values are in `simulink/output/*.json`.

## S6 — Outdated Simulink documentation (Low) — FIXED

**Finding.** `simulink/README.md` (two lines) still described the model as a
Sprint-6 *future* artifact; `docs/ARCHITECTURE.md` §7 and
`docs/TEAM_EXECUTION.md` called the folder "planned artifact / Stubs".

**Fix.** Rewrote `simulink/README.md` (build/run/data-source policy + measured
baseline summary), updated `ARCHITECTURE.md` §7 and `TEAM_EXECUTION.md` to the
committed-and-runnable model with JSON persistence and the measured verdict.

## S7 — KPI instrumentation perturbed measured throughput (High) — FIXED + VERIFIED (MEASURED)

**Finding.** Early work derived the three performance KPIs
(`averageWaitingTime`, `queueLength`, `reviewerUtilization`) from Entity
Replicator counting pairs around the Acquisition Queue and Review Server. The
replicators **throttle the entity flow**: the original entity of a replicator
pair is blocked until every copy is accepted, cutting measured baseline
throughput from **143/day to 97/day** (the counters' occupancy/ratio math was
correct but the measured flow itself was wrong). A first replacement — enabling
the blocks' stat ports during the model build — instead broke model compilation
(`MismatchInputSigHierInfo`: enabling ANY SimEvents stat output on a queue or
server changes entity structure, breaking the Entity Input Switch merges).

**Fix.** Three parts, all verified:
- `simulink/DRTelemedicine.slx` is built **flow-only**; the replicator scheme
  was removed. The build script keeps an `enableStats` flag for experiments.
- `simulink/instrument_for_kpis.m` enables the queue/server statistics
  **post-build, per simulation run** (pure passive listeners), then attaches
  one dedicated To Workspace observer per signal. Enabled after build, SimEvents
  prepends stat ports and pushes the entity port last; the port layout is
  verified dynamically. Queue stat order was confirmed on a controlled
  mini-model by Little's law: `out1 = AverageWait`, `out2 =
  AverageQueueLength` (earlier wiring had these swapped).
- `run_simulink_scenarios`, `smoke_DRTelemedicine`, and `analyze_capacity`
  report the three KPIs as MEASURED (JSON `dataSourcePolicy` labels them so).

**Verification (MEASURED, seed 42, full 8h window).** Baseline throughput is
back to the pristine-model value and the KPIs are real:
- Baseline: `completed = 143/day` (`52,195/yr`), `averageWaitingTime =
  5225 s`, `queueLength = 36.8`, `reviewerUtilization = 5.4%`. The long wait is
  physically consistent: the single acquisition camera plus 10% recapture
  saturates the stage (analytical utilization 100%, ~200 s effective service).
- The full 7-scenario suite reproduces the prior measured throughputs exactly
  (`143 / 130 / 144 / 143 / 143 / 143 / 143`), bottleneck Acquisition; KPI
  values scale correctly across scenarios (e.g. low_load `wait = 1149 s`,
  `qlen = 6.2`; solo_reviewer `revUtil = 10.8%` vs team_5 `2.2%`).
- Smoke run now uses a full workday so the review-server Utilization stat is
  genuinely exercised before it is asserted (a 1h smoke leaves too few
  referrals to depart); PASS with all measured KPIs.
- Result JSON: `simulink/output/district_capacity_results_20260917_180441.json`.

## R1 — Clinical PDF advertised a black zero-map mock as "attention" (Medium) — FIXED + TESTED

**Finding.** PDF page 2 created a Grad-CAM/attention panel whenever the
(placeholder) `computeGradCAM` returned a **nonempty all-black** array, so a
mock run rendered a black image labeled attention — an over-claim under guardrail #3.

**Fix.** `reporting/buildReport.m` now derives availability from **content**, not
call presence: `gradCamAvailable` / `attentionImageAvailable` require
`any(gradCam(:) > 0)`, and `evidenceOverlayAvailable` requires lesion candidates
or a localized optic disc. Images ride in the renderer-only `report.images`
(kept out of machine-readable `report.data`). `reporting/renderReport.m` renders
real panels when available and an honest gray "Not available" placeholder otherwise.

**Verification.** `tests/unit/test_report_visualization.m` (3 tests): mock zero-map
run never advertises attention and is never carried; the original image is always
embedded; genuine non-trivial attention/evidence embeds and renders.
Full MATLAB suite: **223/223 pass**.

## R2 — Quality-gate thresholds never calibrated against a labeled subset (Medium) — PENDING

**Finding.** The Stage-1 gate runs on committed `config/quality_thresholds.m`
defaults; no human-rated quality subset exists in the repo, so agreement /
false-rejection rate (§2 Stage 1) are unmeasured.

**Fix (harness, not numbers).** `scripts/calibrate_quality_gate.m` +
`config/quality_calibration.m` run the REAL `assessQuality()` over
`data/manifests/quality_labels.csv` (grid of low-band/scores, config-driven
objective), persist a metrics JSON audit trail, and — only when enabled — write
the chosen set to `data/models/quality_gate_calibration.mat`, consumed by
`quality_thresholds()`. Missing subset/images/labels raise structured
`RetinaSense:calibrateQualityGate:*` errors and persist NOTHING.

**Verification.** `tests/unit/test_quality_gate_calibration.m` (5 tests): missing
subset / missing image / bad label each raise and persist nothing; a real
synthetic-provenance run computes bounded metrics + JSON audit trail; a persisted
override then activates in `quality_thresholds()` and reverts on teardown.

**Status: PENDING** until a human-rated `quality_labels.csv` is provided → run the
harness → commit metrics + override. Until then the committed defaults stand and
no threshold was changed.

## R3 — Borderline case reclassified 'good' after enhancement, contradicting the routing contract (Medium) — FIXED + TESTED

**Finding.** On the enhancement path, `runPipeline` overwrote `c.quality` with the
post-enhancement recheck, so a case routed as `borderline` ended the pipeline as
`good`. Three tests (`test_B_qualityBorderline`, `test_borderlineEnhanceThenRecheckRouting`,
`test_mockBorderlineCaseLoads`) specify that the gate **routing class** survives
the enhancement, with the recheck outcome recorded as enhancement metadata.

**Fix.** `scripts/runPipeline.m` keeps the Stage-1 routing class on the case when
the enhanced image is adopted; `c.enhancement.recheckClass` / `c.enhancement.improved`
carry the true post-enhancement recheck outcome, and `c.quality` never over-claims
the enhanced pixels.

**Verification.** The three naming tests pass plus the full MATLAB suite:
**223/223 pass** (was 220/223). Backend 59/59, frontend 64/64, typecheck clean,
python verifier all checks pass.

## I1 — Live backend integration audit (real MATLAB engine over HTTP) — VERIFIED

**Scope (2026-09-17).** Drove the real backend (`uvicorn`, `RETINASENSE_SIMULATION=off`,
MATLAB R2026a engine `matlabEngine:true`) with real datasets on this host and observed
the full chain — upload → quality gate → real DR model → calibration → Grad-CAM →
human review → PDF → SQLite.

**Fixes applied.**
- `backend/tests/e2e_live.py` and `backend/tests/smoke_live.py` pointed at the
  non-existent `D:\Project\RetinaSense\...` drive path (missing "s") — corrected to
  `D:\Projects\RetinaSense\...`; candidate discovery and both live suites pass.
- `backend/.env` had `RETINASENSE_EXPLAIN_ENABLED=0` while the real trained model
  (`data/models/resnet50_dr_aptos.pt`) and torch are present on this host. Flipped to
  `1`; the backend then produces genuine Grad-CAM artifacts (screening now exercises the
  full explainability chain instead of honest-empty).

**Verification (live, real engine).**
- `e2e_live.py`: 16 IDRiD/APTOS candidates screened; 15 IDRiD images **honestly
  rejected** by the real gate (`class=ungradable`, reason `focus`, REFOCUS instruction,
  no fabricated grade); APTOS grade-0 accepted → `grade=0` `referable=false`,
  `confidence=0.984` `uncertainty=0.063`, report generated, valid PDF (142,328 bytes).
- `smoke_live.py`: 14/14 PASS — health+engine, auth, real screening, real Grad-CAM
  artifact served as PNG (66,754 bytes), honest gate reject, report + PDF (271,609 bytes),
  human approve review, DB-backed case list/stats.
- DB rows verified for `RS-2026-00017`: `screening_results` (completed/good/grade 0 +
  gradcam path), `human_reviews` (approve, Dr. Meera Rao), `final_decisions`
  (0/No DR/referral 0), `reports` (summary + payload), `images` (relative path, no
  traversal). Backend pytest suite still **59/59**.

## Verification commands (kept current)

```bash
# Python mirror / backend (CI-able)
python -m pytest -q                                                                  # from backend/
python tools/python_verifier/mock_pipeline.py                                        # from repo root

# Live backend integration (needs MATLAB engine on this host + datasets on disk)
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000                         # from backend/
python tests/smoke_live.py                                                            # from backend/ (while server is up)
python tests/e2e_live.py                                                              # from backend/ (while server is up)

# Frontend
npx vitest run tests/cases.test.tsx                                                  # from frontend/
npx tsc --noEmit                                                                      # from frontend/

# MATLAB (on a machine with MATLAB)
runtests('tests')
```