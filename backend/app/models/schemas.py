"""Pydantic models for the RetinaSense backend API.

Mirrors the Case struct from core/newCase.m and the contracts in
docs/ARCHITECTURE.md §4.  All medical fields default to None so the
backend NEVER fabricates values.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


# ---------- Quality (§4.1) ----------

class QualityMetrics(BaseModel):
    focus: float | None = None
    illumination: float | None = None
    fovCoverage: float | None = None
    artifacts: float | None = None


class QualityResult(BaseModel):
    class_: str | None = Field(None, alias="class")
    score: float | None = None
    failureReasons: list[str] = Field(default_factory=list)
    recaptureReason: str | None = None
    recaptureInstruction: str | None = None

    model_config = {"populate_by_name": True}


# ---------- AI Prediction (§4.4–4.6) ----------

class AiPrediction(BaseModel):
    grade: int | None = None
    gradeLabel: str | None = None
    referable: bool | None = None
    confidence: float | None = None
    uncertainty: float | None = None
    reviewRequired: bool | None = None


# ---------- Explainability (§4.5) ----------

class Explainability(BaseModel):
    gradCamAvailable: bool = False
    gradCamPath: str | None = None
    evidenceAvailable: bool = False
    evidencePath: str | None = None


# ---------- Human Review (§4.7) ----------

class HumanReview(BaseModel):
    action: str | None = None
    reviewerId: str | None = None
    overrideGrade: int | None = None
    finalReferral: bool | None = None
    status: str | None = None
    notes: str | None = None
    timestamp: str | None = None


# ---------- Final Decision ----------

class FinalDecision(BaseModel):
    grade: int | None = None
    gradeLabel: str | None = None
    referral: bool | None = None


# ---------- Case metadata ----------

class CaseMeta(BaseModel):
    patientId: str = ""
    eye: str = ""
    phcId: str = ""


# ---------- Request / Response schemas ----------

class CreateCaseResponse(BaseModel):
    caseId: str
    status: str = "created"


class CaseListItem(BaseModel):
    caseId: str
    status: str
    patientId: str = ""
    eye: str = ""
    phcId: str = ""
    createdAt: str | None = None
    referable: bool | None = None


class CaseStats(BaseModel):
    totalCases: int = 0
    screeningsCompleted: int = 0
    pendingReviews: int = 0
    recaptureRequired: int = 0
    reviewed: int = 0
    created: int = 0


class CaseResponse(BaseModel):
    caseId: str
    status: str
    quality: QualityResult
    aiPrediction: AiPrediction
    explainability: Explainability
    humanReview: HumanReview | None = None
    finalDecision: FinalDecision | None = None


class ReviewAction(BaseModel):
    action: str  # approve | override | recapture
    reviewerId: str
    overrideGrade: int | None = None
    finalReferral: bool | None = None
    notes: str = ""


class ReviewResponse(BaseModel):
    caseId: str
    review: HumanReview
    finalDecision: FinalDecision | None = None


class ReportResponse(BaseModel):
    caseId: str
    report: dict[str, Any] | None = None
    summary: str | None = None
    disclaimer: str | None = None


class HealthResponse(BaseModel):
    status: str
    matlabEngine: bool
    version: str
    database: str = "ok"


class ErrorResponse(BaseModel):
    error: dict[str, str]
