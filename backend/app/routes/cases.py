"""Case endpoints: create, get, screen, review, report."""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, File, Form, UploadFile
from fastapi.responses import FileResponse

from ..models.schemas import (
    CaseListItem,
    CaseMeta,
    CaseResponse,
    CaseStats,
    CreateCaseResponse,
    ReviewAction,
    ReviewResponse,
    ReportResponse,
)
from ..services import screening as screening_svc
from ..services import report as report_svc

router = APIRouter()


# ---------- GET /api/cases ----------
@router.get("/api/cases", response_model=list[CaseListItem])
def list_cases() -> list[CaseListItem]:
    return [CaseListItem(**item) for item in screening_svc.list_cases()]


# ---------- GET /api/cases/stats ----------
@router.get("/api/cases/stats", response_model=CaseStats)
def get_stats() -> CaseStats:
    return CaseStats(**screening_svc.case_stats())


# ---------- POST /api/cases ----------
@router.post("/api/cases", response_model=CreateCaseResponse, status_code=201)
def create_case(
    patientId: str = Form(""),
    eye: str = Form(""),
    phcId: str = Form(""),
) -> CreateCaseResponse:
    meta = CaseMeta(patientId=patientId, eye=eye, phcId=phcId)
    case_id = screening_svc.create_case(meta)
    return CreateCaseResponse(caseId=case_id, status="created")


# ---------- POST /api/cases/{caseId}/screen ----------
@router.post(
    "/api/cases/{caseId}/screen",
    response_model=CaseResponse,
    status_code=200,
)
async def screen_case(
    caseId: str,
    image: UploadFile = File(...),
    patientId: str = Form(""),
    eye: str = Form(""),
    phcId: str = Form(""),
) -> CaseResponse:
    meta = CaseMeta(patientId=patientId, eye=eye, phcId=phcId) if patientId or eye or phcId else None
    result = screening_svc.run_screening(
        caseId,
        image.file,
        filename=image.filename or "fundus.jpg",
        content_type=image.content_type or "image/jpeg",
        metadata=meta,
    )

    # Check for recapture (ungradable)
    status = result.get("status", "completed")
    quality = result.get("quality", {})
    quality_class = quality.get("class")

    # Build quality result
    from ..models.schemas import QualityResult, AiPrediction, Explainability, HumanReview, FinalDecision

    quality_resp = QualityResult(
        class_=quality_class,
        score=quality.get("score"),
        failureReasons=quality.get("failureReasons", []),
        recaptureReason=quality.get("recaptureReason"),
        recaptureInstruction=quality.get("recaptureInstruction"),
    )

    ai_pred_data = result.get("aiPrediction")
    ai_pred = AiPrediction(**ai_pred_data) if ai_pred_data else AiPrediction()

    explain_data = result.get("explainability")
    explain = Explainability(**explain_data) if explain_data else Explainability()

    return CaseResponse(
        caseId=caseId,
        status=status,
        quality=quality_resp,
        aiPrediction=ai_pred,
        explainability=explain,
        humanReview=None,
        finalDecision=None,
    )


# ---------- GET /api/cases/{caseId} ----------
@router.get("/api/cases/{caseId}", response_model=CaseResponse)
def get_case(caseId: str) -> CaseResponse:
    data = screening_svc.get_case(caseId)
    if data is None:
        from ..utils.errors import RetinaSenseError, ErrorCode
        raise RetinaSenseError(ErrorCode.CASE_NOT_FOUND, f"Case '{caseId}' not found.")

    from ..models.schemas import QualityResult, AiPrediction, Explainability, HumanReview, FinalDecision

    quality_data = data.get("quality", {})
    quality_resp = QualityResult(
        class_=quality_data.get("class_") or quality_data.get("class"),
        score=quality_data.get("score"),
        failureReasons=quality_data.get("failureReasons", []),
        recaptureReason=quality_data.get("recaptureReason"),
        recaptureInstruction=quality_data.get("recaptureInstruction"),
    )

    ai_pred_data = data.get("aiPrediction")
    ai_pred = AiPrediction(**ai_pred_data) if ai_pred_data else AiPrediction()

    explain_data = data.get("explainability")
    explain = Explainability(**explain_data) if explain_data else Explainability()

    hr_data = data.get("humanReview")
    human_review = HumanReview(**hr_data) if hr_data else None

    fd_data = data.get("finalDecision")
    final_decision = FinalDecision(**fd_data) if fd_data else None

    return CaseResponse(
        caseId=data["caseId"],
        status=data.get("status", "created"),
        quality=quality_resp,
        aiPrediction=ai_pred,
        explainability=explain,
        humanReview=human_review,
        finalDecision=final_decision,
    )


# ---------- POST /api/cases/{caseId}/review ----------
@router.post("/api/cases/{caseId}/review", response_model=ReviewResponse)
def review_case(caseId: str, body: ReviewAction) -> ReviewResponse:
    result = screening_svc.submit_review(
        caseId,
        action=body.action,
        reviewer_id=body.reviewerId,
        override_grade=body.overrideGrade,
        final_referral=body.finalReferral,
        notes=body.notes,
    )

    from ..models.schemas import HumanReview, FinalDecision

    review_data = result.get("review", {})
    human_review = HumanReview(**review_data)

    fd_data = result.get("finalDecision")
    final_decision = FinalDecision(**fd_data) if fd_data else None

    return ReviewResponse(
        caseId=caseId,
        review=human_review,
        finalDecision=final_decision,
    )


# ---------- GET /api/cases/{caseId}/report ----------
@router.get("/api/cases/{caseId}/report", response_model=ReportResponse)
def get_report(caseId: str) -> ReportResponse:
    result = report_svc.get_report(caseId)
    return ReportResponse(**result)


# ---------- POST /api/cases/{caseId}/report ----------
@router.post("/api/cases/{caseId}/report", response_model=ReportResponse)
def generate_report(caseId: str) -> ReportResponse:
    result = report_svc.generate_report(caseId)
    return ReportResponse(**result)


# ---------- GET /api/cases/{caseId}/image ----------
@router.get("/api/cases/{caseId}/image")
def get_case_image(caseId: str) -> FileResponse:
    path = screening_svc.get_case_image(caseId)
    return FileResponse(path)


# ---------- GET /api/cases/{caseId}/artifacts/{artifact} ----------
@router.get("/api/cases/{caseId}/artifacts/{artifact}")
def get_artifact(caseId: str, artifact: str) -> FileResponse:
    """Serve a real explainability artifact (gradcam | evidence).

    Only files produced by the pipeline and persisted under the application's
    artifacts directory are served; the artifact name is whitelisted and the
    case id shape-validated, so path traversal is not possible through this
    endpoint.
    """
    path = screening_svc.get_artifact_path(caseId, artifact)
    return FileResponse(path, media_type="image/png")
