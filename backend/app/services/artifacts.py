"""Explainability artifact I/O for the RetinaSense backend.

Real Grad-CAM/evidence overlays computed by the MATLAB pipeline are matrices in
the Case struct (explain.attentionImage / explain.evidenceOverlay).  The web
panel needs them as image files, so they are persisted per case under an
application-controlled directory:

    backend/data/artifacts/<caseId>/{gradcam,evidence}.png

Only files produced by the pipeline are written — nothing is fabricated.  A
Grad-CAM overlay is kept only when it carries real attention content; an
evidence overlay only when it contains visible (independent) markers.  Serving
always goes through the guarded route, never a user-supplied path, and every
resolution is containment-checked under ARTIFACTS_DIR.
"""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

from ..config import ARTIFACTS_DIR, CASE_ID_PREFIX, CASE_ID_WIDTH
from ..utils.errors import ErrorCode, RetinaSenseError

# Artifact names honouring the API.  Fixed whitelist -> no user-controlled
# filenames -> no traversal through the artifact parameter.
ARTIFACT_NAMES = {"gradcam", "evidence"}

_CASE_ID_RE = re.compile(rf"^{CASE_ID_PREFIX}-\d{{{CASE_ID_WIDTH}}}$")

# API reference URLs returned to the frontend (relative to the backend base URL).
def _path_for(case_id: str, name: str) -> str:
    return f"/api/cases/{case_id}/artifacts/{name}"


def valid_case_id(case_id: str) -> bool:
    """Strict case-id shape check (RS-YYYY-NNNNN). Rejects traversal payloads."""
    return bool(_CASE_ID_RE.match(case_id or ""))


def _artifacts_dir(case_id: str) -> Path:
    # case_id already shape-validated; still fold it to a single leaf segment.
    return ARTIFACTS_DIR / case_id.strip()


def _write_png(case_id: str, name: str, arr: Any) -> Path:
    dest = _artifacts_dir(case_id) / f"{name}.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(arr, mode="RGB").save(dest, format="PNG")
    return dest


def _pixel_count(arr: Any) -> int:
    """Total pixel count of a numpy or matlab.engine array (both call paths)."""
    if arr is None:
        return 0
    try:
        if isinstance(arr, np.ndarray):
            return int(arr.size)
        size = arr.size
        dims = tuple(size()) if callable(size) else tuple(size)
        return int(np.prod(dims)) if dims else 0
    except Exception:
        return 0


def has_attention_content(arr: Any) -> bool:
    """True when a Grad-CAM overlay carries real (non-zero) attention content.

    The honest fallbacks — an all-zero attention image and a uniform flat wash
    (e.g. a degenerate navy-blue blend from an empty heatmap) — both carry no
    discernible attention and are treated as 'unavailable', never displayed.
    """
    if _pixel_count(arr) <= 0:
        return False
    try:
        a = np.asarray(arr, dtype=np.float64)
    except Exception:
        return False
    if a.size == 0:
        return False
    if not bool((a != 0).any()):
        return False
    # Uniform image (every pixel identical): flat colour dump — no attention.
    v0 = a.ravel()[0]
    if not bool((a != v0).any()):
        return False
    # The overlay always includes the fundus base, so real overlays have wide
    # pixel variation; require a little more than numerical noise.
    return float(np.abs(a - v0).max()) > 1.0


def has_visible_markers(rgb: Any) -> bool:
    """An evidence overlay is only worth serving when it marks something.

    computeGradCAM always starts the overlay from a grayscale copy of the fundus
    (equal R/G/B channels) and only paints lesion/optic-disc markers in colour.
    So a true overlay has at least one pixel whose channels differ.
    """
    if _pixel_count(rgb) == 0:
        return False
    return bool((rgb[..., 0] != rgb[..., 2]).any() or (rgb[..., 1] != rgb[..., 2]).any())


def save_explain_artifacts(
    case_id: str,
    *,
    attention: Any | None,
    evidence: Any | None,
) -> dict[str, str | None]:
    """Persist real explainability overlays for a case.

    Returns the safe API references to serve them (None when a given artifact
    was not produced / has nothing to show).  A zero attention image or an
    empty evidence overlay yields None — an honest 'unavailable', never a
    fabricated heatmap or a blank stand-in.
    """
    refs: dict[str, str | None] = {"gradcam": None, "evidence": None}

    if has_attention_content(attention):
        _write_png(case_id, "gradcam", attention)
        refs["gradcam"] = _path_for(case_id, "gradcam")

    if has_visible_markers(evidence):
        _write_png(case_id, "evidence", evidence)
        refs["evidence"] = _path_for(case_id, "evidence")

    return refs


def resolve_artifact_path(case_id: str, name: str) -> Path:
    """Resolve the on-disk artifact for *name* (containment-checked).

    Raises ARTIFACT_UNAVAILABLE (404) for malformed case ids, unknown artifact
    names, missing files, or anything that escapes ARTIFACTS_DIR.
    """
    if not valid_case_id(case_id):
        raise RetinaSenseError(
            ErrorCode.ARTIFACT_UNAVAILABLE,
            f"Malformed case id '{case_id}'.",
            stage="artifacts",
        )
    if name not in ARTIFACT_NAMES:
        raise RetinaSenseError(
            ErrorCode.ARTIFACT_UNAVAILABLE,
            f"Unknown artifact '{name}'.",
            stage="artifacts",
        )
    base = ARTIFACTS_DIR.resolve()
    path = (base / case_id.strip() / f"{name}.png").resolve()
    try:
        path.relative_to(base)
    except ValueError:
        raise RetinaSenseError(
            ErrorCode.ARTIFACT_UNAVAILABLE,
            "Refusing to serve an artifact outside the artifacts directory.",
            stage="artifacts",
        )
    if not path.is_file():
        raise RetinaSenseError(
            ErrorCode.ARTIFACT_UNAVAILABLE,
            f"No {name} artifact is stored for case '{case_id}'.",
            stage="artifacts",
        )
    return path