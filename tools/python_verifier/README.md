# Python verifier (dev-time, MATLAB-less)

CI-able Python mirrors of the MATLAB RetinaSense pipeline and dataset tooling,
so integration integrity and real-model sanity can be checked on machines
without a MATLAB license. These tools are **not product code** — the canonical
runtime is MATLAB — but they exercise the real committed artifacts where the
comment says so.

## Tools

### `real_path_check.py` — real-model regression check

Verifies the **real trained artifact set** is consumed end-to-end exactly as
`scripts/runPipeline.m` does in default (non-mock) mode:

```
load_model(resnet50_dr_aptos.pt)
-> T from resnet50_calib.mat (scipy)
-> inference on real APTOS validation images
```

Requires the real weight files in `data/models/` and a real (small) APTOS
sample; exits nonzero if an artifact is missing or a check fails.

```bash
python tools/python_verifier/real_path_check.py
```

### `dataset_check.py` — dataset integrity verifier

Python mirror of `dataset/buildDatasetManifests.m`, `loadDataset.m`,
`validateDataset.m`. Reports only what is actually on disk:

- **APTOS**: real image count per grade dir + `folds.csv` split integrity +
  a small decode check.
- **IDRiD**: manifest consistency + bounded decode.
- **DRIVE / Messidor-2**: recorded as NOT AVAILABLE (external-validation-only;
  not present on disk — this is expected, not corruption).

```bash
python tools/python_verifier/dataset_check.py
```

### `mock_pipeline.py` — mock contract/orchestration check

`mock_pipeline.py` runs the end-to-end workflow with **mock semantics matched
to the MATLAB mock** (deterministic pseudo-probs, honest empty evidence,
entropy math, recapture guidance) and checks the interface contracts
(`docs/ARCHITECTURE.md §4`). Exits 0 if all contract + orchestration checks
pass.

```bash
python tools/python_verifier/mock_pipeline.py
```

### `experiment_pipeline.py` — real end-to-end ML experiment (PyTorch mirror)

Executable PyTorch mirror of the AI/ML workstream (preprocessing,
classification, calibration, explainability, evaluation). Reports **real
numbers only** and never fabricates metrics (AGENTS.md guardrail #1). Uses the
real trained checkpoint in `data/models/`.

### `gradcam_smoke_test.py` — Grad-CAM explainability smoke test

Mirror of `explainability/computeGradCAM.m` (Stage 7). Uses the saved benchmark
model (`data/models/resnet50_dr_aptos.pt`) and a small APTOS **validation**
sample — no training, no test split, no Messidor-2, no fabricated attention.
Verifies per `docs/ARCHITECTURE.md §4.5`.

## Running the fast CI checks

```bash
python tools/python_verifier/mock_pipeline.py
python tools/python_verifier/dataset_check.py
```