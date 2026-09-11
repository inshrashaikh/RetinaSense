"""Backend configuration for RetinaSense.

All values are prototype-safe defaults. No secrets, no cloud infra.
"""
import os
from pathlib import Path

# Root directories
BACKEND_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = BACKEND_ROOT.parent
DATA_DIR = BACKEND_ROOT / "data"
CASES_DIR = DATA_DIR / "cases"
IMAGES_DIR = DATA_DIR / "images"

# SQLite database
DATABASE_PATH = Path(
    os.environ.get("RETINASENSE_DATABASE_PATH", str(DATA_DIR / "retinasense.db"))
).resolve()

# CORS — allow the Vite dev server and preview origins (also overridable).
_CORS_ENV = os.environ.get("RETINASENSE_CORS_ORIGINS")
CORS_ORIGINS = (
    [o.strip() for o in _CORS_ENV.split(",") if o.strip()]
    if _CORS_ENV
    else [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:4173",
        "http://127.0.0.1:4173",
    ]
)

# Image validation
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png"}
ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}
MAX_IMAGE_SIZE_MB = 20
MAX_IMAGE_SIZE_BYTES = MAX_IMAGE_SIZE_MB * 1024 * 1024

# Case ID
CASE_ID_PREFIX = "RS-2026"
CASE_ID_WIDTH = 5  # zero-padded digits

# MATLAB integration
# set True when MATLAB Runtime/Engine is connected on this host
MATLAB_ENGINE_AVAILABLE = bool(os.environ.get("RETINASENSE_MATLAB_ENGINE", "0") == "1")

# Adapter selection.
#   RETINASENSE_SIMULATION=mock  -> labelled MockMatlabAdapter (demo/CI only,
#                                   no MATLAB needed; output is never clinical).
#   unset / anything else        -> real MatlabAdapter (drives runPipeline).
SIMULATION_MODE = os.environ.get("RETINASENSE_SIMULATION", "off").lower()

# DR grading
GRADE_LABELS = {
    0: "No DR",
    1: "Mild NPDR",
    2: "Moderate NPDR",
    3: "Severe NPDR",
    4: "Proliferative DR",
}
REFER_THRESHOLD = 2  # grade >= this is referable

# Server
HOST = "0.0.0.0"
PORT = 8000
