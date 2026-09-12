"""Local file-system storage for RetinaSense backend cases.

Layout per case:
    backend/data/cases/<caseId>/
        metadata.json
        screening.json
        review.json
        report.json
    backend/data/images/<caseId>/
        <filename>

All paths are safe-checked — no traversal outside DATA_DIR.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from ..config import CASES_DIR, IMAGES_DIR


def _case_dir(case_id: str) -> Path:
    return CASES_DIR / case_id


def _images_dir(case_id: str) -> Path:
    return IMAGES_DIR / case_id


def _safe_write(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, default=str), encoding="utf-8")


def _safe_read(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


# ---------- Public API ----------

def create_case_dir(case_id: str) -> None:
    """Create the storage directories for a new case."""
    _case_dir(case_id).mkdir(parents=True, exist_ok=True)
    _images_dir(case_id).mkdir(parents=True, exist_ok=True)


def case_exists(case_id: str) -> bool:
    return _case_dir(case_id).exists()


def save_metadata(case_id: str, data: dict[str, Any]) -> None:
    _safe_write(_case_dir(case_id) / "metadata.json", data)


def load_metadata(case_id: str) -> dict[str, Any] | None:
    return _safe_read(_case_dir(case_id) / "metadata.json")


def save_screening(case_id: str, data: dict[str, Any]) -> None:
    _safe_write(_case_dir(case_id) / "screening.json", data)


def load_screening(case_id: str) -> dict[str, Any] | None:
    return _safe_read(_case_dir(case_id) / "screening.json")


def save_review(case_id: str, data: dict[str, Any]) -> None:
    _safe_write(_case_dir(case_id) / "review.json", data)


def load_review(case_id: str) -> dict[str, Any] | None:
    return _safe_read(_case_dir(case_id) / "review.json")


def save_report(case_id: str, data: dict[str, Any]) -> None:
    _safe_write(_case_dir(case_id) / "report.json", data)


def load_report(case_id: str) -> dict[str, Any] | None:
    return _safe_read(_case_dir(case_id) / "report.json")


def save_image(case_id: str, filename: str, data: bytes) -> Path:
    """Save uploaded image and return its path.

    Filenames are sanitised: only the stem is kept, extension is preserved.
    """
    safe_stem = Path(filename).stem
    safe_ext = Path(filename).suffix.lower()
    if not safe_ext:
        safe_ext = ".png"
    safe_name = f"{safe_stem}{safe_ext}"
    dest = _images_dir(case_id) / safe_name
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return dest


def load_image_path(case_id: str) -> Path | None:
    img_dir = _images_dir(case_id)
    if not img_dir.exists():
        return None
    files = list(img_dir.iterdir())
    return files[0] if files else None


def load_all(case_id: str) -> dict[str, Any] | None:
    """Load every stored JSON for a case.  Returns None if case dir missing."""
    if not case_exists(case_id):
        return None
    meta = load_metadata(case_id) or {}
    screening = load_screening(case_id) or {}
    review = load_review(case_id)
    report = load_report(case_id)
    return {
        "metadata": meta,
        "screening": screening,
        "review": review,
        "report": report,
    }
