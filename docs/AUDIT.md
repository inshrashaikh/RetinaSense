# RetinaSense Audit

Status: **open**. Findings below were raised and fixed in the 2026-09 sprint. This
file records each finding, its resolution, and the evidence/verification behind it.
Nothing here is a clinical claim; every metric mentioned comes from a real
`evaluation/`-style run (see guardrail #1) or is explicitly marked MOCK.

Scope reviewed: backend FastAPI + auth, enhancement-recheck grading path, clinical
PDF report, MATLAB analysis modules (guardrail #2 config hygiene), repo hygiene,
and frontend test health.

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

Deferred / not yet actionable:

| ID | Item | Note |
|----|------|------|
| D1 | Experiment artifacts | `experiment_pipeline.py` full run deferred; existing artifacts are stale, must be regenerated before any metric claim |
| D2 | MATLAB execution | `.m` module edits verified by review + Python-side tests only; run `runtests('tests')` on a MATLAB box to confirm |

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

## Verification commands (kept current)

```bash
# Python mirror / backend (CI-able)
& "C:\Users\shahu\AppData\Local\Temp\opencode\retinasense-venv\Scripts\python.exe" -m pytest -q   # from backend/
python tools/python_verifier/mock_pipeline.py                                                        # from repo root

# Frontend
npx vitest run tests/cases.test.tsx                                                                  # from frontend/

# MATLAB (on a machine with MATLAB)
runtests('tests')
```