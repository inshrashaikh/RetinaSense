"""Health check endpoint."""
from __future__ import annotations

from fastapi import APIRouter

from ..config import MATLAB_ENGINE_AVAILABLE
from ..models.schemas import HealthResponse

router = APIRouter()


@router.get("/api/health", response_model=HealthResponse)
def health_check() -> HealthResponse:
    return HealthResponse(
        status="ok",
        matlabEngine=MATLAB_ENGINE_AVAILABLE,
        version="0.1.0-prototype",
    )
