# RetinaSense — database layer

The backend persists cases in a **single-file SQLite database** (SQLAlchemy 2.x
ORM) instead of per-case JSON files.

- Database file: `backend/data/retinasense.db` (overridable via the
  `RETINASENSE_DATABASE_PATH` environment variable).
- Image **bytes** stay on disk under `backend/data/images/<caseId>/`
  (no BLOBs). The database stores image metadata plus the path **relative to
  `DATA_DIR`**; the image endpoint resolves it safely and never serves a path
  outside the data directory.
- Code layout:
  - `backend/app/db/models.py` — SQLAlchemy ORM models (tables below).
  - `backend/app/db/session.py` — `configure_database(path)`, `init_db()`,
    `session_scope()`.
  - `backend/app/storage/database_store.py` — storage API that mirrors the old
    `local_store` function names so `services/screening.py` and
    `services/report.py` are the only layer that knows where data lives.

## Tables

| Table                | Purpose                                                        | Notes |
|----------------------|----------------------------------------------------------------|-------|
| `cases`              | One row per case; opaque id, status, patient/eye/PHC metadata  | `case_id` unique |
| `images`             | Uploaded image metadata + relative path                        | bytes on disk |
| `screening_results`  | **AI result**: quality gate + `aiPrediction` + explainability  | one row per case, written once |
| `human_reviews`      | Human review entry (action, reviewer, notes, …)                | one row per case |
| `final_decisions`    | Final decision (grade, label, referral) derived from review    | one row per case |
| `reports`            | Report payload + summary + disclaimer                          | one row per case |

Nested payloads (`quality`, `aiPrediction`, `explainability`, the review
entry, and the report payload) are stored as **JSON columns** so the exact
dict shapes round-trip — the API contract has not changed.

## Guardrails enforced by the schema

1. **AI and human final decision are separate.** `screening_results` (the AI
   result) is a distinct table from `human_reviews` + `final_decisions`. The
   review path writes only the review/final-decision rows; nothing in the
   screening path can be mutated by a human override. Test
   `test_review_does_not_touch_screening_row` proves it.
2. **No path traversal.** `ImageRecord.relative_path` is joined under
   `DATA_DIR` and validated with `relative_to`; the store returns `None` for
   any path that resolves outside it. Test `test_image_path_rejects_traversal`.
3. **No PII.** patient id remains an opaque token; the schema never stores
   personal data, and image endpoints return only the stored file.

## Case IDs

`backend/app/utils/case_id.py` derives the next sequence number from the
database (`max_case_sequence`), so IDs continue across server restarts instead
of resetting. Format stays `RS-2026-NNNNN`.

## New HTTP endpoints

- `GET /api/cases` — list stored cases (newest first) as `CaseListItem[]`
  (`caseId`, `status`, `patientId`, `eye`, `phcId`, `createdAt`).
- `GET /api/cases/{caseId}/image` — serves the stored fundus image
  (`FileResponse`). 404 `CASE_NOT_FOUND` for unknown cases and
  `IMAGE_UNAVAILABLE` when the case has no image on disk.

Assert-protection: paths are resolved via the DB-stored relative path only —
the API never accepts or echoes a filesystem path from the client.

## Migration from the old layout

New stores only. The previous `backend/data/cases/<caseId>/` JSON files are no
longer read or written; existing test/legacy case files are not auto-imported.
Image files under `backend/data/images/` that an earlier run stored without a
DB row are not served by the new image endpoint (correct — the endpoint only
serves what the current storage layer can trace).