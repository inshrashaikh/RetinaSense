"""Screening service — orchestration logic between the API and MATLAB adapter.

Handles:
- image validation (type, size)
- case creation + storage
- calling the MATLAB adapter
- quality gate (early exit for ungradable)
- storing structured results
"""
from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any, BinaryIO

from ..config import (
    ALLOWED_IMAGE_EXTENSIONS,
    ALLOWED_IMAGE_TYPES,
    GRADE_LABELS,
    MAX_IMAGE_SIZE_BYTES,
    REFER_THRESHOLD,
)
from ..models.schemas import (
    AiPrediction,
    CaseResponse,
    CaseMeta,
    Explainability,
    FinalDecision,
    QualityResult,
)
from ..services.matlab_adapter import BaseMatlabAdapter
from ..storage import database_store
from ..utils.case_id import next_case_id
from ..utils.errors import ErrorCode, RetinaSenseError


def validate_image(
    *,
    content_type: str | None = None,
    filename: str | None = None,
    size: int | None = None,
) -> None:
    """Validate image upload parameters.  Raises RetinaSenseError on failure."""
    if content_type and content_type.lower() not in ALLOWED_IMAGE_TYPES:
        raise RetinaSenseError(
            ErrorCode.UNSUPPORTED_FILE_TYPE,
            f"Unsupported file type '{content_type}'. "
            f"Allowed: {', '.join(sorted(ALLOWED_IMAGE_TYPES))}.",
            stage="validation",
        )
    if filename:
        ext = Path(filename).suffix.lower()
        if ext not in ALLOWED_IMAGE_EXTENSIONS:
            raise RetinaSenseError(
                ErrorCode.UNSUPPORTED_FILE_TYPE,
                f"Unsupported file extension '{ext}'. "
                f"Allowed: {', '.join(sorted(ALLOWED_IMAGE_EXTENSIONS))}.",
                stage="validation",
            )
    if size is not None and size > MAX_IMAGE_SIZE_BYTES:
        raise RetinaSenseError(
            ErrorCode.IMAGE_TOO_LARGE,
            f"Image size {size} bytes exceeds the {MAX_IMAGE_SIZE_BYTES} byte limit.",
            stage="validation",
        )
    if size is not None and size == 0:
        raise RetinaSenseError(
            ErrorCode.INVALID_IMAGE,
            "Uploaded image is empty (0 bytes).",
            stage="validation",
        )


def create_case(meta: CaseMeta | None = None) -> str:
    """Create a new case and persist metadata.  Returns caseId."""
    case_id = next_case_id()
    database_store.create_case_dir(case_id)
    meta_dict = meta.model_dump() if meta else {}
    database_store.save_metadata(case_id, meta_dict)
    return case_id


def run_screening(
    case_id: str,
    image_data: BinaryIO,
    *,
    filename: str = "fundus.jpg",
    content_type: str = "image/jpeg",
    metadata: CaseMeta | None = None,
    adapter: BaseMatlabAdapter | None = None,
) -> dict[str, Any]:
    """Run the full screening pipeline for a case.

    Returns the structured screening result dict (not a CaseResponse — the
    caller formats it).
    """
    if not database_store.case_exists(case_id):
        raise RetinaSenseError(
            ErrorCode.CASE_NOT_FOUND,
            f"Case '{case_id}' not found.",
            stage="storage",
        )

    # Save image
    img_bytes = image_data.read()
    validate_image(
        content_type=content_type,
        filename=filename,
        size=len(img_bytes),
    )
    img_path = database_store.save_image(case_id, filename, img_bytes)

    # Persist metadata if provided
    if metadata:
        database_store.save_metadata(case_id, metadata.model_dump())

    # Run MATLAB adapter
    if adapter is None:
        from ..services.matlab_adapter import default_adapter
        adapter = default_adapter()

    meta_dict = database_store.load_metadata(case_id) or {}
    result = adapter.run_pipeline(str(img_path), meta_dict)

    # Quality gate: early exit for ungradable
    quality_data = result.get("quality", {})
    quality_class = quality_data.get("class", "")

    screening: dict[str, Any] = {
        "quality": quality_data,
        "aiPrediction": None,
        "explainability": None,
        "status": "completed",
    }

    if quality_class == "ungradable":
        screening["status"] = "recapture_required"
        database_store.save_screening(case_id, screening)
        return screening

    grading_data = result.get("grading")
    calibrated_data = result.get("calibrated")
    explain_data = result.get("explain")

    # Build AI prediction (never fabricated — only from adapter output)
    if grading_data and calibrated_data:
        grade = grading_data.get("grade")
        screening["aiPrediction"] = {
            "grade": grade,
            "gradeLabel": GRADE_LABELS.get(grade, "Unknown") if grade is not None else None,
            "referable": grading_data.get("referable"),
            "confidence": calibrated_data.get("confidence"),
            "uncertainty": calibrated_data.get("uncertainty"),
            "reviewRequired": calibrated_data.get("reviewRequired"),
        }

    # Explainability
    if explain_data:
        screening["explainability"] = {
            "gradCamAvailable": explain_data.get("gradCamAvailable", False),
            "gradCamPath": explain_data.get("gradCamPath"),
            "evidenceAvailable": explain_data.get("evidenceAvailable", False),
            "evidencePath": explain_data.get("evidencePath"),
        }
    else:
        screening["explainability"] = {
            "gradCamAvailable": False,
            "gradCamPath": None,
            "evidenceAvailable": False,
            "evidencePath": None,
        }

    database_store.save_screening(case_id, screening)
    return screening


def get_case(case_id: str) -> dict[str, Any] | None:
    """Load all stored data for a case and build the full response dict."""
    all_data = database_store.load_all(case_id)
    if all_data is None:
        return None
    screening = all_data.get("screening", {})
    review_data = all_data.get("review")
    report_data = all_data.get("report")

    quality = screening.get("quality", {})
    ai_pred = screening.get("aiPrediction")
    explain = screening.get("explainability")
    status = screening.get("status", "created")

    human_review = None
    final_decision = None
    if review_data:
        human_review = review_data.get("review")
        final_decision = review_data.get("finalDecision")

    return {
        "caseId": case_id,
        "status": status,
        "quality": quality,
        "aiPrediction": ai_pred,
        "explainability": explain,
        "humanReview": human_review,
        "finalDecision": final_decision,
    }


def submit_review(
    case_id: str,
    *,
    action: str,
    reviewer_id: str,
    override_grade: int | None = None,
    final_referral: bool | None = None,
    notes: str = "",
) -> dict[str, Any]:
    """Process a human review action.

    AI prediction is NEVER overwritten.  Review is stored separately.
    """
    if not database_store.case_exists(case_id):
        raise RetinaSenseError(
            ErrorCode.CASE_NOT_FOUND,
            f"Case '{case_id}' not found.",
            stage="storage",
        )

    valid_actions = {"approve", "override", "recapture"}
    if action not in valid_actions:
        raise RetinaSenseError(
            ErrorCode.INVALID_REVIEW,
            f"Invalid action '{action}'. Must be one of: {', '.join(sorted(valid_actions))}.",
            stage="review",
        )

    if action == "override" and (override_grade is None or override_grade < 0 or override_grade > 4):
        raise RetinaSenseError(
            ErrorCode.INVALID_REVIEW,
            "overrideGrade must be an integer 0..4 for override action.",
            stage="review",
        )

    # Load existing screening to get AI grade for immutability checks
    screening = database_store.load_screening(case_id) or {}
    ai_pred = screening.get("aiPrediction")
    ai_grade = ai_pred.get("grade") if ai_pred else None

    if action == "approve":
        final_grade = ai_grade
        if final_grade is not None:
            referral = final_grade >= REFER_THRESHOLD
        else:
            referral = False
    elif action == "override":
        final_grade = override_grade
        referral = final_grade >= REFER_THRESHOLD
    else:  # recapture
        final_grade = None
        referral = False

    grade_label = GRADE_LABELS.get(final_grade, "Pending") if final_grade is not None else "Pending"

    review_entry = {
        "action": action,
        "reviewerId": reviewer_id,
        "overrideGrade": override_grade,
        "finalReferral": referral,
        "status": "overridden" if action == "override"
        else ("approved" if action == "approve" else "recapture"),
        "notes": notes,
    }
    final_decision = {
        "grade": final_grade,
        "gradeLabel": grade_label,
        "referral": referral,
    }

    database_store.save_review(case_id, {
        "review": review_entry,
        "finalDecision": final_decision,
        "aiGradeImmutable": True,
    })

    return {
        "caseId": case_id,
        "review": review_entry,
        "finalDecision": final_decision,
    }


def list_cases() -> list[dict[str, Any]]:
    """Return all stored cases (most recently created first)."""
    return database_store.list_cases()


def case_stats() -> dict[str, Any]:
    """Aggregate counts for the dashboard stat cards."""
    return database_store.case_stats()


def get_case_image(case_id: str) -> Path:
    """Resolve the stored fundus image path for a case.

    Raises CASE_NOT_FOUND if the case does not exist and IMAGE_UNAVAILABLE
    if the case has no image on disk.
    """
    if not database_store.case_exists(case_id):
        raise RetinaSenseError(
            ErrorCode.CASE_NOT_FOUND,
            f"Case '{case_id}' not found.",
            stage="storage",
        )
    path = database_store.load_image_path(case_id)
    if path is None:
        raise RetinaSenseError(
            ErrorCode.IMAGE_UNAVAILABLE,
            f"No fundus image is stored for case '{case_id}'.",
            stage="storage",
        )
    return path
