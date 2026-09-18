"""RetinaSense Backend — FastAPI application.

Prototype REST API bridging the web frontend to the MATLAB AI engine.
Not clinical infrastructure — see README for scope.
"""
from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import CASES_DIR, CORS_ORIGINS, IMAGES_DIR, MATLAB_ENGINE_AVAILABLE
from .db.session import configure_database, init_db
from .routes import auth, cases, health, simulation
from .services import auth as auth_svc
from .storage import database_store
from .utils.errors import RetinaSenseError


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Ensure data directories exist, initialise the database, and seed the
    demo accounts on startup."""
    CASES_DIR.mkdir(parents=True, exist_ok=True)
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    configure_database()
    init_db()
    auth_svc.seed_users()
    # Legacy review rows stored reviewer_id as the USERNAME (e.g. "doctor")
    # instead of the display name — backfill them on every start (idempotent).
    database_store.backfill_reviewer_names(auth_svc.username_to_name())
    yield


app = FastAPI(
    title="RetinaSense Backend",
    description=(
        "Prototype REST API for the RetinaSense diabetic retinopathy "
        "screening system. Bridges web frontend to MATLAB AI engine."
    ),
    version="0.2.0-prototype",
    lifespan=lifespan,
)

# CORS — bearer-token auth means cookies are never sent, so every origin may
# call the API once it carries a valid token. Default allow-list is ["*"]
# (see config.py); `RETINASENSE_CORS_ORIGINS` can pin explicit origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)


# ---------- Global exception handler ----------
@app.exception_handler(RetinaSenseError)
async def retina_sense_error_handler(request: Request, exc: RetinaSenseError):
    return JSONResponse(
        status_code=exc.status_code,
        content=exc.detail,
    )


# ---------- Root: basic service information ----------
@app.get("/", include_in_schema=True)
def root_status() -> dict[str, str]:
    """Basic service information and status for the RetinaSense backend."""
    return {
        "service": "RetinaSense Backend",
        "version": "0.2.0-prototype",
        "health": "/api/health",
        "docs": "/docs",
        "matlabEngine": "connected" if MATLAB_ENGINE_AVAILABLE else "unavailable",
        "auth": "/api/auth/login",
        "note": "Screening decision-support prototype. No clinical diagnosis.",
    }


# ---------- Routes ----------
app.include_router(health.router)
app.include_router(auth.router)
app.include_router(cases.router)
app.include_router(simulation.router)
