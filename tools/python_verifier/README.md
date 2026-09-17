# Python verifier (dev-time, MATLAB-less)

A dependency-free mirror of the mock pipeline used to run the
end-to-end workflow and its contract checks in CI / on machines without MATLAB.

- It mirrors the interface contracts (`docs/ARCHITECTURE.md §4`) and the
  orchestration order of `scripts/runPipeline.m`.
- It is NOT product code and NOT a competing implementation. The canonical
  runtime is MATLAB; this mirror exists so integration integrity is checked
  without a MATLAB license.
- Mock semantics are identical to the MATLAB mock: deterministic pseudo-probs,
  honest empty evidence, entropy math, recapture guidance.

Run:

```bash
python tools/python_verifier/mock_pipeline.py
```

Exits 0 if all contract + orchestration checks pass.