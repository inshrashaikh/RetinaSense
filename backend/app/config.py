"""Backend configuration for RetinaSense.

All values are prototype-safe defaults. No secrets, no cloud infra.
"""
import os
from pathlib import Path

# Load environment variables from backend/.env when present (dev/local use).
# python-dotenv does NOT override variables already set in the environment,
# so CI/production env vars always take precedence.
try:
    from dotenv import load_dotenv as _load_dotenv

    _env_file = Path(__file__).resolve().parent.parent / ".env"
    if _env_file.is_file():
        _load_dotenv(_env_file, override=False)
except ImportError:  # python-dotenv not installed — that is fine
    pass

# Root directories
BACKEND_ROOT = Path(__file__).resolve().parent.parent
REPOSITORY_ROOT = BACKEND_ROOT.parent
DATA_DIR = BACKEND_ROOT / "data"
CASES_DIR = DATA_DIR / "cases"
IMAGES_DIR = DATA_DIR / "images"
ARTIFACTS_DIR = DATA_DIR / "artifacts"
REPORTS_DIR = DATA_DIR / "reports"
MODELS_DIR = REPOSITORY_ROOT / "data" / "models"

# District-scale capacity model (simulink/)
SIMULINK_DIR = REPOSITORY_ROOT / "simulink"
SIMULATION_OUTPUT_DIR = SIMULINK_DIR / "output"

# 100k/yr scalability target (SIH 2026 problem statement). Reference only —
# never claimed as measured; the simulation reports actual throughput.
SIM_TARGET_ANNUAL_PATIENTS = 100_000
SIM_WORKDAYS_PER_YEAR = 365  # matches simulink/scenario_params.m (274/day ≈ 100k/365)

# SQLite database
DATABASE_PATH = Path(
    os.environ.get("RETINASENSE_DATABASE_PATH", str(DATA_DIR / "retinasense.db"))
).resolve()

# CORS — the app authenticates with bearer tokens (never cookies), so any
# origin may call the API once it HAS a token. Default is therefore to allow
# every origin; `RETINASENSE_CORS_ORIGINS` can still pin an explicit list.
_CORS_ENV = os.environ.get("RETINASENSE_CORS_ORIGINS")
CORS_ORIGINS = (
    [o.strip() for o in _CORS_ENV.split(",") if o.strip()]
    if _CORS_ENV
    else ["*"]
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
# The engine is considered available when the matlab.engine Python package can
# be imported on this host. Set RETINASENSE_MATLAB_ENGINE=1 to force-enable or
# =0 to force-disable (e.g. CI machines without the MATLAB engine package).

# --- MATLAB DLL bootstrap (Windows only) ------------------------------------
# On Windows, matlab/__init__.py calls os.add_dll_directory() *inside* the
# module body, but the DLL loader caches the first lookup result. If bin\win64
# is not already registered via os.add_dll_directory() before the first
# `import matlab` statement, the transitive DLL load for
# matlabmultidimarrayforpython.pyd fails even though bin\win64 is on PATH.
# We pre-register it here so that the import below always succeeds.
_MATLAB_BIN_WIN64 = Path(
    os.environ.get(
        "MATLAB_BIN_WIN64",
        r"C:\Program Files\MATLAB\R2026a\bin\win64",
    )
)
_MATLAB_EXTERN_BIN_WIN64 = Path(
    os.environ.get(
        "MATLAB_EXTERN_BIN_WIN64",
        r"C:\Program Files\MATLAB\R2026a\extern\bin\win64",
    )
)
_MATLAB_ENGINE_WIN64 = Path(
    os.environ.get(
        "MATLAB_ENGINE_WIN64",
        r"C:\Program Files\MATLAB\R2026a\extern\engines\python\dist\matlab\engine\win64",
    )
)

import sys as _sys

if os.name == "nt":  # Windows only
    try:
        if _MATLAB_BIN_WIN64.is_dir():
            os.add_dll_directory(str(_MATLAB_BIN_WIN64))
        if _MATLAB_EXTERN_BIN_WIN64.is_dir():
            os.add_dll_directory(str(_MATLAB_EXTERN_BIN_WIN64))
        if _MATLAB_ENGINE_WIN64.is_dir() and str(_MATLAB_ENGINE_WIN64) not in _sys.path:
            _sys.path.insert(0, str(_MATLAB_ENGINE_WIN64))
        if _MATLAB_EXTERN_BIN_WIN64.is_dir() and str(_MATLAB_EXTERN_BIN_WIN64) not in _sys.path:
            _sys.path.insert(0, str(_MATLAB_EXTERN_BIN_WIN64))
    except Exception:
        pass  # Non-fatal: if the dirs don't exist the import will fail below
# ---------------------------------------------------------------------------

_MATLAB_ENGINE_IMPORTABLE = False
try:
    import matlab.engine  # type: ignore[import-not-found]  # noqa: F401

    _MATLAB_ENGINE_IMPORTABLE = True
except (ImportError, OSError):  # pragma: no cover - depends on host setup
    _MATLAB_ENGINE_IMPORTABLE = False

MATLAB_ENGINE_AVAILABLE = (
    os.environ.get("RETINASENSE_MATLAB_ENGINE", "auto").lower() != "0"
    and _MATLAB_ENGINE_IMPORTABLE
)

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

# Explainability — real PyTorch Grad-CAM (mirror of explainability/computeGradCAM.m).
#   RETINASENSE_EXPLAIN_ENABLED=1  -> compute real attention from the trained
#                                     PyTorch model (data/models/<backbone>_dr_aptos.pt)
#   unset / 0                       -> honest empty (gradCamAvailable=false)
EXPLAIN_ENABLED = os.environ.get("RETINASENSE_EXPLAIN_ENABLED", "1") == "1"
EXPLAIN_BACKBONE = os.environ.get("RETINASENSE_EXPLAIN_BACKBONE", "resnet50").lower()
EXPLAIN_MODEL_PATH = MODELS_DIR / f"{EXPLAIN_BACKBONE}_dr_aptos.pt"
EXPLAIN_INPUT_SIZE = 224
EXPLAIN_MEAN = [0.485, 0.456, 0.406]
EXPLAIN_STD = [0.229, 0.224, 0.225]
EXPLAIN_REFER_THRESHOLD = REFER_THRESHOLD

# ---------------------------------------------------------------------------
# Authentication (prototype-grade, stdlib-only)
# ---------------------------------------------------------------------------

# Signing secret for bearer tokens. MUST be set to a strong random value in
# deployment (e.g. `python -c "import secrets;print(secrets.token_hex(32))"`).
# The dev fallback is derived from the machine so local sessions are stable
# but never used as a "real" secret.
TOKEN_SECRET = os.environ.get(
    "RETINASENSE_TOKEN_SECRET",
    "retinasense-dev-secret-do-not-use-in-prod",
)
TOKEN_EXPIRY_HOURS = float(os.environ.get("RETINASENSE_TOKEN_EXPIRY_HOURS", "24"))

# Seed accounts created on startup (dev/demo friendly; change passwords for
# any shared deployment). role: 'phc_operator' | 'ophthalmologist' | 'admin'.
SEED_USERS = [
    {
        "username": "operator",
        "name": "PHC Operator",
        "role": "phc_operator",
        "password": os.environ.get("RETINASENSE_OPERATOR_PASSWORD", "operator123"),
    },
    {
        "username": "doctor",
        "name": "Dr. Meera Rao",
        "role": "ophthalmologist",
        "password": os.environ.get("RETINASENSE_DOCTOR_PASSWORD", "doctor123"),
    },
    {
        "username": "admin",
        "name": "District Admin",
        "role": "admin",
        "password": os.environ.get("RETINASENSE_ADMIN_PASSWORD", "admin123"),
    },
]
