# RetinaSense Backend

FastAPI service bridging the web frontend to the RetinaSense DR-screening
engine. The AI engine is MATLAB (`scripts/runPipeline.m` + `core/`,
`preprocessing/`, `classification/`, `calibration/`, `explainability/`,
`reporting/`), bridged through the MATLAB Engine for Python; explainability is
also backed by the real PyTorch model. This is **prototype infrastructure, not
production clinical software**.

## Tech stack

- **Python** + **FastAPI** + **Pydantic v2**
- **SQLite** persistence via **SQLAlchemy 2.x** (single file, no server;
  `backend/data/retinasense.db`, path overridable with
  `RETINASENSE_DATABASE_PATH`). A Postgres URL is supported for a containerised
  deployment (`RETINASENSE_DATABASE_URL`), but SQLite is the default.
- **matlabengine** (real MATLAB Engine for Python) for the screening adapter.
- **PyTorch** (CPU build) + the real `resnet50_dr_aptos.pt` for Grad-CAM.
- **pytest** + **httpx** for tests.

## Scope

The MATLAB implementation is the **source of truth**. The backend only bridges
to it and **never fabricates medical output**: the MATLAB adapter runs the real
pipeline and the explainability service runs genuine Grad-CAM on the actual
model. Referral/grade values always come from a real run, never from fallback
logic.

## Directory structure

```
backend/
├── app/
│   ├── main.py                 # FastAPI app + error handler
│   ├── config.py               # validation limits, paths, MATLAB/flags
│   ├── auth_deps.py            # role-based auth on protected routes
│   ├── db/                     # SQLAlchemy models + session (SQLite/Postgres)
│   ├── models/schemas.py       # Pydantic request/response models
│   ├── routes/
│   │   ├── auth.py             # /api/auth/login, /api/auth/me
│   │   ├── cases.py            # /api/cases, screen, review, report, artifacts
│   │   ├── health.py           # /api/health
│   │   └── simulation.py       # /api/simulation/capacity
│   ├── services/
│   │   ├── matlab_adapter.py   # MATLAB Engine bridge (real runPath)
│   │   ├── screening.py        # screen/review orchestration
│   │   ├── explainability.py   # real PyTorch Grad-CAM (resnet50_dr_aptos.pt)
│   │   ├── report.py           # report + pdf_report generation
│   │   └── artifacts.py        # artifact storage/serving
│   ├── storage/
│   │   ├── database_store.py   # DB-backed storage API
│   │   └── local_store.py      # legacy file-based store (kept for tests)
│   └── utils/                  # errors.py, case_id.py, security.py
├── tests/                      # pytest suites (API, DB, Grad-CAM, simulation)
└── requirements.txt
```

## API

| Method | Path                          | Purpose                              |
|--------|-------------------------------|--------------------------------------|
| POST   | `/api/auth/login`             | Sign in a seeded user                |
| GET    | `/api/auth/me`                | Current session/role                 |
| GET    | `/api/health`                 | Backend + MATLAB engine status       |
| POST   | `/api/cases`                  | Create a case → opaque `RS-2026-NNNNN` |
| GET    | `/api/cases`                  | List cases (newest first)            |
| GET    | `/api/cases/stats`            | Case statistics                      |
| POST   | `/api/cases/{id}/screen`      | Upload fundus image, run pipeline    |
| GET    | `/api/cases/{id}`             | Full case result                     |
| POST   | `/api/cases/{id}/review`      | Human review (approve/override/recapture) |
| GET    | `/api/cases/{id}/report`      | Stored report (404 if none generated)|
| POST   | `/api/cases/{id}/report`      | Generate the report                  |
| GET    | `/api/cases/{id}/report/pdf`  | PDF download of the report           |
| GET    | `/api/cases/{id}/image`       | Original fundus image                |
| GET    | `/api/cases/{id}/artifacts/{name}` | Grad-CAM/explainability artifact |
| GET    | `/api/simulation/capacity`    | District capacity model results      |

Errors are structured:

```json
{ "error": { "code": "CASE_NOT_FOUND", "message": "..." } }
```

Codes: `INVALID_IMAGE`, `UNSUPPORTED_FILE_TYPE`, `IMAGE_TOO_LARGE`,
`UNGRADABLE_IMAGE`, `MODEL_UNAVAILABLE`, `MATLAB_ENGINE_UNAVAILABLE`,
`CASE_NOT_FOUND`, `INVALID_REVIEW`, `REPORT_UNAVAILABLE`, `IMAGE_UNAVAILABLE`,
`ARTIFACT_UNAVAILABLE`, `UNAUTHORIZED`, `FORBIDDEN`, `INTERNAL_ERROR`.

## MATLAB integration

`app/services/matlab_adapter.py` defines the adapter contract:

```
Backend → MatlabAdapter → runPipeline(case) → Case result → Backend JSON
```

`MatlabAdapter` runs the **real** MATLAB engine (`runPipeline` with the
committed model `resnet50_dr_aptos.mat` and calibration `resnet50_calib.mat` in
`data/models/`). When the MATLAB engine is unavailable it returns
`MATLAB_ENGINE_UNAVAILABLE` (HTTP 503) — it never returns fake predictions.
A `MockMatlabAdapter` exists **TEST-ONLY** for CI/plumbing checks and is never
used in the inference path.

Enable/disable via `backend/.env`: `RETINASENSE_MATLAB_ENGINE=1`,
`RETINASENSE_MATLAB_MOCK=0`. The engine path points at the MATLAB R2026a
installation on the dev box.

## Explainability

`app/services/explainability.py` loads the real PyTorch checkpoint
(`data/models/resnet50_dr_aptos.pt`), runs genuine Grad-CAM, and serves the
attention overlay as a PNG artifact. Output is annotated as model attention,
not proof of causality. Runs only when `RETINASENSE_EXPLAIN_ENABLED=1`.

## Storage

Cases, screening results, reviews, final decisions, and reports live in SQLite
(`backend/data/retinasense.db`, tables `cases`, `images`,
`screening_results`, `human_reviews`, `final_decisions`, `reports`). Image
bytes stay on disk under `backend/data/images/<caseId>/`; the DB stores
relative paths only and never serves a path outside `data/`. Case IDs are
opaque (`RS-2026-00001`); no patient PII is stored.

## Security (prototype level)

- MIME type + extension + size validation for uploads
- Sanitised filenames; no path traversal (`relative_to` checks)
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

See also `tools/e2e_smoke.py` for a full-stack smoke check against a running
backend.