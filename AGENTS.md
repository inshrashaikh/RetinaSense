# AGENTS.md — RetinaSense team conventions

Conventions and commands for anyone (human or agent) working in this repo.

## Guardrails (non-negotiable)

1. **No fabricated metrics/results.** Any number that looks like accuracy/SE/SP/
   ECE/kappa comes from `evaluation/` and a real experiment, or it is labeled
   MOCK. Classifier/validation functions `raiseError` until they are real.
2. **No hard-coded thresholds/config.** Everything lives in `config/`
   (`experiment_config.m`, `quality_thresholds.m`, `preprocess_config.m`,
   `classification_config.m`).
3. **No fake AI.** Placeholder modules return *honest empty* outputs
   (e.g. empty vessel mask, zero Grad-CAM map) plus a `note` — never invented
   detections or attention.
4. **Quality gate gates.** Ungradable → recapture feedback and early exit; the
   grader never sees an ungradable image.
5. **Analysis is advisory, non-blocking.** `analysis/` failure never changes
   grading/referral.
6. **Messidor-2 is external-validation only.** Never in train/val.
7. **No PII.** Patient id is an opaque token; no secrets in the repo.

## Command conventions

No MATLAB on the shared dev box — the canonical runtime is MATLAB, the CI-able
mirror is Python:

```bash
# lint-ish / smoke test (fast, no MATLAB needed)
python tools/python_verifier/mock_pipeline.py

# MATLAB (on a machine with MATLAB):
#   results = runtests('tests')
#   demo_mock_pipeline
```

## Interface rules

- Every module = one stable contract in `docs/ARCHITECTURE.md §4`.
- Signature, `Case` fields, error identifiers, and config keys must stay stable.
- Errors via `core/raiseError(stage, code, msg)` →
  `RetinaSense:<stage>:<code>`.
- Logging only via `core/logMessage(level, stage, msg)`.

## TODO markers

Real-ML work is marked in-code as `TODO(Sprint N...)`. Keep markers precise and
remove them only when the real implementation lands. Do not claim a Sprint is
done without tests updated and the honest path exercised.

## Definition of done for a module swap

- Same contract I/O and `Case` fields.
- Config-driven (no new magic numbers).
- Reports real behavior on test inputs; the old mock is removed (not dead code).
- No clinical claim without `evaluation/` numbers.