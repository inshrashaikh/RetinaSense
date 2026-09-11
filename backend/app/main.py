"""RetinaSense Backend — FastAPI application.

Prototype REST API bridging the web frontend to the MATLAB AI engine.
Not clinical infrastructure — see README for scope.
"""
from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .config import CASES_DIR, IMAGES_DIR
from .routes import cases, health
from .utils.errors import RetinaSenseError


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Ensure data directories exist on startup."""
    CASES_DIR.mkdir(parents=True, exist_ok=True)
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    yield


app = FastAPI(
    title="RetinaSense Backend",
    description=(
        "Prototype REST API for the RetinaSense diabetic retinopathy "
        "screening system. Bridges web frontend to MATLAB AI engine."
    ),
    version="0.1.0-prototype",
    lifespan=lifespan,
)


# ---------- Global exception handler ----------
@app.exception_handler(RetinaSenseError)
async def retina_sense_error_handler(request: Request, exc: RetinaSenseError):
    return JSONResponse(
        status_code=exc.status_code,
        content=exc.detail,
    )


# ---------- Routes ----------
app.include_router(health.router)
app.include_router(cases.router)
