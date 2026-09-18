"""MatlabAdapter — bridge between the Python backend and the MATLAB RetinaSense pipeline.

Contract (docs/ARCHITECTURE.md §4):
    Backend -> MatlabAdapter -> runPipeline(case) -> Case result -> Backend JSON

Real path (MatlabAdapter): when the MATLAB Engine for Python is connected
(config.MATLAB_ENGINE_AVAILABLE), the backend calls the actual MATLAB pipeline
(`scripts/runPipeline.m`) once per case with ``mock=False`` — i.e. the real
trained model + calibration artifacts gated by ``cfg.model.available``.  The
resulting Case is mapped field-by-field onto the API response shape; nothing is
invented and every medical value comes straight from the MATLAB module output.
If MATLAB (or the trained artifacts) is missing, a structured
MATLAB_ENGINE_UNAVAILABLE / MODEL_UNAVAILABLE error is raised — never a
fabricated result.

Demo/CI path (MockMatlabAdapter): TEST-ONLY.  Returns deterministic honest
placeholder values mirroring the MATLAB mock pipeline's ``mock=true`` mode, is
clearly labelled, and is ONLY selected explicitly — from tests directly, or via
the RETINASENSE_SIMULATION=mock environment flag (see services.screening
default_adapter).  It exists so the full backend/UI flow can run end-to-end
without MATLAB; its output is never presented as a clinical screening result.
"""
from __future__ import annotations

import abc
import math
import os
import threading
from pathlib import Path
from typing import Any

from ..config import MATLAB_ENGINE_AVAILABLE, REPOSITORY_ROOT
from ..models.schemas import (
    AiPrediction,
    Explainability,
    QualityResult,
)
from ..utils.errors import ErrorCode, RetinaSenseError

# Process-wide shared MATLAB session (see MatlabAdapter._ensure_engine).
_ENGINE: Any | None = None
_ENGINE_LOCK = threading.Lock()


class BaseMatlabAdapter(abc.ABC):
    """Abstract adapter interface."""

    @abc.abstractmethod
    def run_pipeline(
        self,
        image_path: str,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        """Run the full RetinaSense pipeline on *image_path*.

        Returns a dict whose shape mirrors the Case struct fields needed
        by the API response (quality, grading, calibrated, explain, review,
        report).

        Raises RetinaSenseError on failure.
        """


class MatlabAdapter(BaseMatlabAdapter):
    """Production adapter — drives the REAL MATLAB pipeline via the engine."""

    def __init__(
        self,
        *,
        engine: Any | None = None,
        scripts_dir: str | None = None,
    ) -> None:
        self._engine = engine
        self._scripts_dir = scripts_dir

    def _ensure_engine(self) -> Any:
        # Shared across requests: starting a fresh MATLAB session + loading the
        # 90MB trained net per screening is too slow for a live deployment.
        global _ENGINE
        if self._engine is not None:
            return self._engine
        if _ENGINE is not None:
            self._engine = _ENGINE
            return self._engine
        if not MATLAB_ENGINE_AVAILABLE:
            raise RetinaSenseError(
                ErrorCode.MATLAB_ENGINE_UNAVAILABLE,
                "MATLAB Engine for Python is not available on this host. "
                "Keep RETINASENSE_SIMULATION unset and configure MATLAB, or set "
                "RETINASENSE_SIMULATION=mock to exercise the labelled mock path.",
                stage="matlab_adapter",
            )
        with _ENGINE_LOCK:
            if _ENGINE is not None:
                self._engine = _ENGINE
                return self._engine
            try:
                import matlab.engine  # type: ignore[import-not-found]

                engine = matlab.engine.start_matlab()
                root = Path(self._scripts_dir or REPOSITORY_ROOT)
                engine.addpath(str(root), nargout=0)
                repo_paths = engine.genpath(str(root), nargout=1)
                if repo_paths:
                    engine.addpath(repo_paths, nargout=0)
                _ENGINE = engine
                self._engine = _ENGINE
                return self._engine
            except Exception as exc:  # pragma: no cover - host-specific
                raise RetinaSenseError(
                    ErrorCode.MATLAB_ENGINE_UNAVAILABLE,
                    f"Could not start MATLAB Engine: {exc}",
                    stage="matlab_adapter",
                )

    def run_pipeline(
        self,
        image_path: str,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        # Check the production dependency first so an unavailable MATLAB
        # engine is never masked by a secondary image-path error.
        eng = self._ensure_engine()
        if not image_path or not os.path.exists(image_path):
            raise RetinaSenseError(
                ErrorCode.IMAGE_UNAVAILABLE,
                f"The uploaded fundus image was not found on disk: {image_path!r}",
                stage="matlab_adapter",
            )

        with _ENGINE_LOCK:  # MATLAB engine calls are not thread-safe
            try:
                # mock flag for runPipeline: real screening by default.
                # RETINASENSE_MATLAB_MOCK is an explicit opt-in to the labelled
                # placeholder pipeline; there is NO auto-fallback when the real
                # model is missing — the structured error is surfaced instead.
                _mock_flag = (
                    os.environ.get("RETINASENSE_MATLAB_MOCK", "0").lower() == "1"
                )

                case_raw = eng.runPipeline(
                    self._to_matlab_meta(metadata),
                    str(image_path),
                    "mock",
                    _mock_flag,
                    nargout=1,
                )
                case = _to_py(case_raw)
            except RetinaSenseError:
                raise
            except Exception as exc:  # pragma: no cover - host-specific
                msg = str(exc)
                _is_missing_model = (
                    "RetinaSense:runPipeline:MissingModel" in msg
                    or "MissingModel" in msg
                    or "No trained model" in msg
                )
                if _is_missing_model:
                    raise RetinaSenseError(
                        ErrorCode.MODEL_UNAVAILABLE,
                        "The trained model/calibration artifacts are missing. "
                        "Run scripts/benchmark_backbones.m + run_all_experiments.m on a "
                        "MATLAB host first, or set RETINASENSE_MATLAB_MOCK=1 in backend/.env "
                        "to run the labelled no-model placeholder pipeline.",
                        stage="matlab_adapter",
                    )
                raise RetinaSenseError(
                    ErrorCode.MATLAB_ENGINE_UNAVAILABLE,
                    f"MATLAB pipeline failed: {msg}",
                    stage="matlab_adapter",
                )

        if not isinstance(case, dict) or "quality" not in case:
            raise RetinaSenseError(
                ErrorCode.INTERNAL_ERROR,
                "MATLAB pipeline returned a malformed Case (no quality field).",
                stage="matlab_adapter",
            )

        return self._map_case(case)

    def _to_matlab_meta(self, metadata: dict[str, Any]) -> dict[str, Any]:
        """Pass through opaque metadata; MATLAB runPipeline accepts a struct."""
        return {k: v for k, v in metadata.items() if k in ("patientId", "eye", "phcId")}

    def _map_case(self, case: dict[str, Any]) -> dict[str, Any]:
        """Map the MATLAB Case onto the API adapter output shape.

        Only values actually present in the returned Case are used.  A missing
        field results in an explicit None/False — never an invented number.
        """
        quality = case.get("quality") or {}
        q_class = quality.get("class")
        if not q_class:
            raise RetinaSenseError(
                ErrorCode.INTERNAL_ERROR,
                "MATLAB quality gate returned no class.",
                stage="matlab_adapter",
            )

        mapped_quality: dict[str, Any] = {
            "class": q_class,
            "score": quality.get("score"),
            "failureReasons": list(quality.get("failureReasons") or []),
        }
        recapture = quality.get("recapture") or {}
        mapped_quality["recaptureReason"] = recapture.get("reasonCode")
        mapped_quality["recaptureInstruction"] = recapture.get("instruction")

        result: dict[str, Any] = {
            "quality": mapped_quality,
            "grading": None,
            "calibrated": None,
            "explain": None,
            "review": None,
        }

        if q_class == "ungradable":
            return result  # early exit at the quality gate — nothing graded

        grading = case.get("grading") or {}
        calibrated = case.get("calibrated") or {}
        explain = case.get("explain") or {}

        if grading:
            result["grading"] = {
                "rawProbs": _vector(grading.get("rawProbs"), 5),
                "grade": _scalar_int(grading.get("grade")),
                "referableProb": _scalar(grading.get("referableProb")),
                "referable": _scalar_bool(grading.get("referable")),
                "modelFile": grading.get("modelFile") or "",
            }

        if calibrated:
            result["calibrated"] = {
                "calibratedProbs": _vector(calibrated.get("calibratedProbs"), 5),
                "confidence": _scalar(calibrated.get("confidence")),
                "uncertainty": _scalar(calibrated.get("uncertainty")),
                "reviewRequired": _scalar_bool(calibrated.get("reviewRequired")),
            }

        if explain:
            result["explain"] = {
                "gradCamAvailable": bool(explain.get("gradCam") is not None),
                "gradCamPath": None,
                "evidenceAvailable": bool(explain.get("evidenceOverlay") is not None),
                "evidencePath": None,
                "note": explain.get("note"),
            }

        return result

    def stop(self) -> None:  # pragma: no cover - host-specific
        """Release the shared MATLAB engine so the process can exit cleanly."""
        global _ENGINE
        engine = self._engine or _ENGINE
        if engine is not None:
            try:
                engine.quit()
            except Exception:
                pass
        _ENGINE = None
        self._engine = None


class MockMatlabAdapter(BaseMatlabAdapter):
    """TEST-ONLY / RETINASENSE_SIMULATION=mock adapter.

    Returns deterministic honest placeholder values (mirrors the MATLAB
    pipeline's mock=true mode).  DO NOT use for real inference — its output is
    never clinical.
    """

    def __init__(self, *, scenario: str = "good"):
        """
        scenario: 'good' | 'borderline' | 'ungradable'
        """
        self.scenario = scenario

    def run_pipeline(
        self,
        image_path: str,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        if self.scenario == "ungradable":
            return {
                "quality": {
                    "class": "ungradable",
                    "score": 0.12,
                    "failureReasons": ["illumination", "fovCoverage"],
                    "recaptureReason": "LOW_ILLUMINATION",
                    "recaptureInstruction": (
                        "Image is too dark. Please ensure adequate lighting "
                        "and re-capture the fundus image."
                    ),
                },
                "grading": None,
                "calibrated": None,
                "explain": None,
                "review": None,
            }

        if self.scenario == "borderline":
            quality = {
                "class": "borderline",
                "score": 0.45,
                "failureReasons": ["illumination"],
                "recaptureReason": None,
                "recaptureInstruction": None,
            }
        else:  # good
            quality = {
                "class": "good",
                "score": 0.91,
                "failureReasons": [],
                "recaptureReason": None,
                "recaptureInstruction": None,
            }

        return {
            "quality": quality,
            "grading": {
                "rawProbs": [0.60, 0.20, 0.10, 0.05, 0.05],
                "grade": 0,
                "referableProb": 0.20,
                "referable": False,
            },
            "calibrated": {
                "calibratedProbs": [0.58, 0.21, 0.11, 0.05, 0.05],
                "confidence": 0.58,
                "uncertainty": 0.25,
                "reviewRequired": False,
            },
            "explain": {
                "gradCamAvailable": False,
                "evidenceAvailable": False,
            },
            "review": None,
        }


def default_adapter() -> BaseMatlabAdapter:
    """Select the screening adapter from configuration.

    - RETINASENSE_SIMULATION=mock -> MockMatlabAdapter (labelled demo/CI only).
    - otherwise -> MatlabAdapter (real MATLAB pipeline; raises a clean error
      when MATLAB or the trained artifacts are unavailable).
    """
    from .. import config

    if config.SIMULATION_MODE == "mock":
        return MockMatlabAdapter()
    return MatlabAdapter()


# --------------------------------------------------------------------------
# MATLAB <-> Python value conversion helpers
# --------------------------------------------------------------------------

def _to_py(value: Any) -> Any:
    """Shallow-to-deep conversion from matlab.engine return values to python."""
    if hasattr(value, "_fieldnames"):  # matlab struct -> dict
        return {name: _to_py(getattr(value, name)) for name in value._fieldnames()}
    if isinstance(value, dict):        # nested python dict (sub-struct)
        return {k: _to_py(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_py(v) for v in value]
    if hasattr(value, "size") and isinstance(value, object) and not isinstance(value, (str, bytes)):
        # matlab.double / matlab.logical array
        try:
            flat = _to_floats(value)
            if flat is None:
                return value
            return flat[0] if len(flat) == 1 else flat
        except (TypeError, ValueError):
            return value
    return value


def _to_floats(value: Any) -> list[float] | None:
    """Flatten a MATLAB numeric array into a list of python floats.

    Iterating a matlab.double of shape (1,5) yields ROW arrays, so a naive
    ``[float(v) for v in value]`` fails.  numpy flattens over all elements and
    handles any shape/scalar cell the engine can return.
    """
    try:
        import numpy as np

        arr = np.asarray(value, dtype=float)
        return [float(v) for v in arr.flatten()] if arr.size else []
    except (TypeError, ValueError):
        return None


def _scalar(value: Any) -> float | None:
    if value is None or isinstance(value, str):
        return None
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    # Honest: a NaN/inf from the REAL MATLAB engine means "no decided scalar
    # here" — exactly like a null. We never fabricate a number from it
    # (Starlette also refuses to serialise NaN to JSON, so this prevents 500s).
    if math.isnan(v) or math.isinf(v):
        return None
    return v


def _scalar_int(value: Any) -> int | None:
    v = _scalar(value)
    if v is None:
        return None
    # Honest: a NaN/Nan/inf from the REAL MATLAB engine means "no decided
    # scalar here" — exactly like a null. We never fabricate a grade by
    # rounding a NaN to 0. Return None so the frontend shows an honest empty.
    if math.isnan(v) or math.isinf(v):
        return None
    return int(v)


def _scalar_bool(value: Any) -> bool | None:
    v = _scalar(value)
    return bool(int(v)) if v is not None else None


def _vector(value: Any, length: int) -> list[float] | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        value = [value]
    try:
        items = _to_floats(value)
    except (TypeError, ValueError):
        return None
    if items is None:
        return None
    if len(items) != length:
        return None
    # Same honest rule as _scalar: a vector containing NaN/inf carries no
    # usable numbers — drop it entirely rather than serialising non-finite.
    if any(math.isnan(v) or math.isinf(v) for v in items):
        return None
    return items