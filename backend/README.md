# RetinaSense Backend

Prototype REST API bridging the web frontend to the MATLAB RetinaSense AI
engine. This is **prototype infrastructure, not production clinical software**.

## Tech stack

- **Python 3.13** + **FastAPI** + **Pydantic v2**
- **Local JSON/file storage** (no database, no cloud)
- **pytest** + **httpx** for API tests

## Scope

The MATLAB implementation (`scripts/runPipeline.m`, `core/newCase.m`, and the
`preprocessing/`, `analysis/`, `classification/`, `explainability/`,
`calibration/`, `reporting/`, `evaluation/` modules) is the **source of truth**.
The backend only bridges to it and **never fabricates medical output**.

## Directory structure

```
backend/
├── app/
│   ├── main.py                 # FastAPI app + error handler
│   ├── config.py               # validation limits, paths, MATLAB flag
│   ├── models/schemas.py       # Pydantic request/response models
│   ├── routes/                 # /api/health, /api/cases...
│   ├── services/
│   │   ├── matlab_adapter.py   # MATLAB Engine bridge (+ TEST-ONLY mock)
│   │   ├── screening.py        # screen/review orchestration
│   │   └── report.py           # report adapter (REPORT_UNAVAILABLE unless stored)
│   ├── storage/local_store.py  # per-case JSON + image files
│   └── utils/                  # errors.py, case_id.py
├── tests/                      # 18 API/service tests
├── data/                       # runtime storage (gitignored)
└── requirements.txt
```

## API

| Method | Path                          | Purpose                              |
|--------|-------------------------------|--------------------------------------|
| GET    | `/api/health`                 | Backend + MATLAB engine status       |
| POST   | `/api/cases`                  | Create a case → opaque `RS-2026-NNNNN` |
| POST   | `/api/cases/{id}/screen`      | Upload fundus image, run pipeline    |
| GET    | `/api/cases/{id}`             | Full case result                     |
| POST   | `/api/cases/{id}/review`      | Human review (approve/override/recapture) |
| GET    | `/api/cases/{id}/report`      | Stored report (401-like code if none)|

Errors are structured:

```json
{ "error": { "code": "CASE_NOT_FOUND", "message": "..." } }
```

Codes: `INVALID_IMAGE`, `UNSUPPORTED_FILE_TYPE`, `IMAGE_TOO_LARGE`,
`UNGRADABLE_IMAGE`, `MODEL_UNAVAILABLE`, `MATLAB_ENGINE_UNAVAILABLE`,
`CASE_NOT_FOUND`, `INVALID_REVIEW`, `REPORT_UNAVAILABLE`, `INTERNAL_ERROR`.

## MATLAB integration

`app/services/matlab_adapter.py` defines the adapter contract:

```
Backend → MatlabAdapter → runPipeline(case) → Case result → Backend JSON
```

The production `MatlabAdapter` returns `MATLAB_ENGINE_UNAVAILABLE` (HTTP 503)
until MATLAB Engine for Python is connected. **It never returns fake
predictions.**

`MockMatlabAdapter` is **TEST-ONLY** — it returns deterministic placeholder
values to exercise the API plumbing and is never used in the inference path.

### Connecting MATLAB (future deployment step)

1. Install MATLAB Runtime + the `matlabengine` Python package
   (`pip install matlabengine`).
2. Set `MATLAB_ENGINE_AVAILABLE = True` in `app/config.py`.
3. Implement `MatlabAdapter.run_pipeline` using `matlab.engine`:
   - convert the uploaded image path / metadata to the MATLAB `meta` struct,
   - call `runPipeline(meta, imagePath)`,
   - map the returned `Case` fields onto the JSON schema
     (`quality`, `grading`, `calibrated`, `explain`, `review`, `report`).

## Storage

Per case, under `backend/data/` (gitignored):

```
data/
├── cases/<caseId>/metadata.json, screening.json, review.json, report.json
└── images/<caseId>/<sanitised filename>
```

Case IDs are opaque (`RS-2026-00001`), no patient PII is stored.

## Security (prototype level)

- MIME type + extension + size validation for uploads
- Sanitised filenames; no path traversal (storage confined to `data/`)
- No secrets, no credentials, no keys in the repo
- Response models validated by Pydantic
- No stack traces leaked to clients (structured error handler)

This is a prototype, not production clinical infrastructure.

## Run

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload        # http://127.0.0.1:8000
```

## Test

```bash
cd backend
python -m pytest tests -v
```