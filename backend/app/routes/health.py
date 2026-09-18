"""Health check endpoint."""
from __future__ import annotations

from fastapi import APIRouter
from sqlalchemy import text

from ..config import MATLAB_ENGINE_AVAILABLE
from ..db.session import session_scope
from ..models.schemas import HealthResponse

router = APIRouter()


def _database_status() -> str:
    """Return 'ok' if the SQLite database responds to a trivial query."""
    try:
        with session_scope() as s:
            s.execute(text("SELECT 1"))
        return "ok"
    except Exception:
        return "unavailable"


@router.get("/api/health", response_model=HealthResponse)
def health_check() -> HealthResponse:
    return HealthResponse(
        status="ok",
        matlabEngine=MATLAB_ENGINE_AVAILABLE,
        database=_database_status(),
        version="0.2.0-prototype",
    )
