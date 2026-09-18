"""SQLite-backed storage for RetinaSense backend cases.

Cases, screening results, human reviews, final decisions and reports live in
the database (backend/data/retinasense.db).  Image BYTES stay on the local
disk under IMAGES_DIR — the database only stores image metadata plus the
relative path, so the new image endpoint can serve them safely.

Public function names mirror the previous local_store API so the orchestration
services (screening.py, report.py) are the only layer that knows *where* data
lives.  The old JSON files are no longer written; local_store keeps only the
image byte I/O and path sanitisation.

Guardrail: screening_results (AI) and human_reviews/final_decisions live in
separate tables — a human override can never mutate the AI result row.  The
images table is never consulted for medical output.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from ..config import DATA_DIR
from ..db.models import (
    CaseRecord,
    FinalDecisionRecord,
    HumanReviewRecord,
    ImageRecord,
    ReportRecord,
    ScreeningRecord,
)
from ..db.session import session_scope
from . import local_store


def create_case_dir(case_id: str) -> None:
    """Register a new case in the database (idempotent)."""
    with session_scope() as s:
        row = s.query(CaseRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            s.add(CaseRecord(case_id=case_id, status="created"))


def case_exists(case_id: str) -> bool:
    with session_scope() as s:
        return s.query(CaseRecord.case_id).filter_by(case_id=case_id).first() is not None


def save_metadata(case_id: str, data: dict[str, Any]) -> None:
    with session_scope() as s:
        row = s.query(CaseRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            row = CaseRecord(case_id=case_id)
            s.add(row)
        row.patient_id = str(data.get("patientId", "") or "")
        row.eye = str(data.get("eye", "") or "")
        row.phc_id = str(data.get("phcId", "") or "")


def load_metadata(case_id: str) -> dict[str, Any] | None:
    with session_scope() as s:
        row = s.query(CaseRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            return None
        return {"patientId": row.patient_id, "eye": row.eye, "phcId": row.phc_id}


def save_screening(case_id: str, data: dict[str, Any]) -> None:
    """Upsert the screening result.  Returns without touching any review row."""
    with session_scope() as s:
        row = s.query(ScreeningRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            row = ScreeningRecord(case_id=case_id)
            s.add(row)
        row.status = str(data.get("status", "completed"))
        row.quality = data.get("quality") or None
        row.ai_prediction = data.get("aiPrediction") or None
        row.explainability = data.get("explainability") or None


def load_screening(case_id: str) -> dict[str, Any] | None:
    with session_scope() as s:
        row = s.query(ScreeningRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            return None
        return {
            "status": row.status,
            "quality": row.quality if row.quality is not None else {},
            "aiPrediction": row.ai_prediction,
            "explainability": row.explainability,
            "createdAt": row.created_at,
        }


def backfill_reviewer_names(name_by_username: dict[str, str]) -> int:
    """Migrate legacy review rows whose reviewer is stored as a USERNAME.

    Earlier builds stamped reviews with ``reviewer_id = username`` (e.g.
    "doctor"); reviews must carry the display name ("Dr. Meera Rao"). This is
    idempotent: only rows whose current value matches a known username (but
    not already a name) are rewritten, in both the column and the JSON payload.
    Returns the number of rows updated.
    """
    updated = 0
    with session_scope() as s:
        rows = s.query(HumanReviewRecord).all()
        for row in rows:
            cur = row.reviewer_id or ""
            name = name_by_username.get(cur)
            if not name or name == cur:
                continue
            row.reviewer_id = name
            payload = dict(row.payload or {})
            if payload.get("reviewerId") == cur:
                payload["reviewerId"] = name
                row.payload = payload
            updated += 1
    return updated


def save_review(case_id: str, data: dict[str, Any]) -> None:
    """Persist a human review AND the final decision — never the AI row."""
    review_entry = data.get("review") or {}
    final_decision = data.get("finalDecision") or {}
    with session_scope() as s:
        row = s.query(HumanReviewRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            row = HumanReviewRecord(case_id=case_id)
            s.add(row)
        row.action = str(review_entry.get("action", ""))
        row.reviewer_id = str(review_entry.get("reviewerId", ""))
        row.override_grade = review_entry.get("overrideGrade")
        row.final_referral = review_entry.get("finalReferral")
        row.status = str(review_entry.get("status", ""))
        row.notes = str(review_entry.get("notes", ""))
        row.ai_grade_immutable = bool(data.get("aiGradeImmutable", True))
        row.payload = dict(review_entry)

        fd = s.query(FinalDecisionRecord).filter_by(case_id=case_id).one_or_none()
        if fd is None:
            fd = FinalDecisionRecord(case_id=case_id)
            s.add(fd)
        fd.grade = final_decision.get("grade")
        fd.grade_label = final_decision.get("gradeLabel")
        fd.referral = final_decision.get("referral")


def load_review(case_id: str) -> dict[str, Any] | None:
    """Reconstruct the review + finalDecision + immutability marker."""
    with session_scope() as s:
        row = s.query(HumanReviewRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            return None
        fd = s.query(FinalDecisionRecord).filter_by(case_id=case_id).one_or_none()
        return {
            "review": dict(row.payload or {}),
            "finalDecision": {
                "grade": fd.grade if fd else None,
                "gradeLabel": fd.grade_label if fd else None,
                "referral": fd.referral if fd else None,
            },
            "aiGradeImmutable": row.ai_grade_immutable,
        }


def save_report(case_id: str, data: dict[str, Any]) -> None:
    with session_scope() as s:
        row = s.query(ReportRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            row = ReportRecord(case_id=case_id)
            s.add(row)
        row.payload = dict(data)
        row.summary = data.get("summary")
        row.disclaimer = data.get("disclaimer")


def load_report(case_id: str) -> dict[str, Any] | None:
    with session_scope() as s:
        row = s.query(ReportRecord).filter_by(case_id=case_id).one_or_none()
        if row is None:
            return None
        return dict(row.payload or {})


# ---------- Images (bytes stay on disk; DB tracks metadata + relative path) ----------

def _content_type_for(ext: str) -> str:
    return "image/png" if ext.lower() == ".png" else "image/jpeg"


def save_image(case_id: str, filename: str, data: bytes) -> Path:
    """Write image bytes to disk (sanitised path) and record metadata."""
    path = local_store.save_image(case_id, filename, data)
    with session_scope() as s:
        s.add(
            ImageRecord(
                case_id=case_id,
                filename=path.name,
                relative_path=path.relative_to(DATA_DIR).as_posix(),
                content_type=_content_type_for(path.suffix),
                size_bytes=len(data),
            )
        )
    return path


def load_image_records(case_id: str) -> list[dict[str, Any]]:
    with session_scope() as s:
        rows = (
            s.query(ImageRecord)
            .filter_by(case_id=case_id)
            .order_by(ImageRecord.id)
            .all()
        )
        return [
            {
                "filename": r.filename,
                "relativePath": r.relative_path,
                "contentType": r.content_type,
                "sizeBytes": r.size_bytes,
                "createdAt": r.created_at,
            }
            for r in rows
        ]


def load_image_path(case_id: str) -> Path | None:
    """Path of the most recently stored image, if it still exists on disk."""
    with session_scope() as s:
        row = (
            s.query(ImageRecord)
            .filter_by(case_id=case_id)
            .order_by(ImageRecord.id.desc())
            .first()
        )
        if row is None:
            return None
    base = DATA_DIR.resolve()
    path = (base / row.relative_path)
    try:
        path.relative_to(base)
    except ValueError:
        return None
    return path if path.is_file() else None


def load_all(case_id: str) -> dict[str, Any] | None:
    """Load every stored record for a case.  Returns None if case missing."""
    if not case_exists(case_id):
        return None
    meta = load_metadata(case_id) or {}
    screening = load_screening(case_id) or {}
    review = load_review(case_id)
    report = load_report(case_id)
    return {
        "metadata": meta,
        "screening": screening,
        "review": review,
        "report": report,
    }


def list_cases() -> list[dict[str, Any]]:
    """Return all cases, most recently created first.

    ``status`` is the *effective* status of the case so the frontend sees
    ``created | completed | recapture_required | reviewed`` instead of just
    ``created`` for every row.
    """
    with session_scope() as s:
        case_rows = (
            s.query(CaseRecord)
            .order_by(CaseRecord.id.desc())
            .all()
        )
        screening_rows = {
            r.case_id: r
            for r in s.query(ScreeningRecord).all()
        }
        review_rows = {
            r.case_id: r
            for r in s.query(HumanReviewRecord).all()
        }

    items: list[dict[str, Any]] = []
    for row in case_rows:
        scr = screening_rows.get(row.case_id)
        has_review = review_rows.get(row.case_id) is not None
        if scr is None:
            status = row.status  # typically "created"
        elif scr.status == "recapture_required":
            status = "recapture_required"
        elif has_review:
            status = "reviewed"
        else:
            status = "completed"
        items.append(
            {
                "caseId": row.case_id,
                "status": status,
                "patientId": row.patient_id,
                "eye": row.eye,
                "phcId": row.phc_id,
                "createdAt": row.created_at,
            }
        )
    return items


def case_stats() -> dict[str, Any]:
    """Aggregate counts used by the dashboard stat cards.

    Effective statuses come from list_cases: 'created' (no screening yet),
    'completed' (screening done, awaiting human review), 'reviewed' (human
    review recorded), 'recapture_required'.
    """
    cases = list_cases()
    total = len(cases)
    created = sum(1 for c in cases if c["status"] == "created")
    completed = sum(1 for c in cases if c["status"] == "completed")
    recapture = sum(1 for c in cases if c["status"] == "recapture_required")
    reviewed = sum(1 for c in cases if c["status"] == "reviewed")
    return {
        "totalCases": total,
        "screeningsCompleted": completed + reviewed,
        "pendingReviews": completed,
        "recaptureRequired": recapture,
        "reviewed": reviewed,
        "created": created,
    }


def max_case_sequence(prefix: str) -> int:
    """Highest numeric suffix of any stored case id with the given prefix."""
    with session_scope() as s:
        rows = s.query(CaseRecord.case_id).all()
    max_seq = 0
    for (cid,) in rows:
        if cid.startswith(prefix):
            try:
                max_seq = max(max_seq, int(cid.split("-")[-1]))
            except ValueError:
                continue
    return max_seq