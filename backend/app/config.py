"""Backend configuration for RetinaSense.

All values are prototype-safe defaults. No secrets, no cloud infra.
"""
from pathlib import Path

# Root directories
BACKEND_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = BACKEND_ROOT / "data"
CASES_DIR = DATA_DIR / "cases"
IMAGES_DIR = DATA_DIR / "images"

# Image validation
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png"}
ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}
MAX_IMAGE_SIZE_MB = 20
MAX_IMAGE_SIZE_BYTES = MAX_IMAGE_SIZE_MB * 1024 * 1024

# Case ID
CASE_ID_PREFIX = "RS-2026"
CASE_ID_WIDTH = 5  # zero-padded digits

# MATLAB integration
MATLAB_ENGINE_AVAILABLE = False  # set True when MATLAB Runtime/Engine is connected

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
