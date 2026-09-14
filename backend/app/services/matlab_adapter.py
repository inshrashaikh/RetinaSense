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
fabricated result.  Input-data failures in the ingest stage (undecodable /
non-RGB uploads) map to a 400 INVALID_IMAGE error; the pipeline never invents
a screening for them.

Demo/CI path (MockMatlabAdapter): TEST-ONLY.  Returns deterministic honest
placeholder values mirroring the MATLAB mock pipeline's ``mock=true`` mode, is
clearly labelled, and is ONLY selected explicitly — from tests directly, or via
the RETINASENSE_SIMULATION=mock environment flag (see services.screening
default_adapter).  It exists so the full backend/UI flow can run end-to-end
without MATLAB; its output is never presented as a clinical screening result.
"""
from __future__ import annotations

import abc
from pathlib import Path
from typing import Any

import numpy as np

from ..config import MATLAB_ENGINE_AVAILABLE, REPOSITORY_ROOT
from ..models.schemas import (
    AiPrediction,
    Explainability,
    QualityResult,
)
from ..utils.errors import ErrorCode, RetinaSenseError


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
        if self._engine is not None:
            return self._engine
        if not MATLAB_ENGINE_AVAILABLE:
            raise RetinaSenseError(
                ErrorCode.MATLAB_ENGINE_UNAVAILABLE,
                "MATLAB Engine for Python is not available on this host. "
                "Keep RETINASENSE_SIMULATION unset and configure MATLAB, or set "
                "RETINASENSE_SIMULATION=mock to exercise the labelled mock path.",
                stage="matlab_adapter",
            )
        try:
            import matlab.engine  # type: ignore[import-not-found]

            self._engine = matlab.engine.start_matlab()
            root = Path(self._scripts_dir or REPOSITORY_ROOT)
            self._engine.addpath(self._engine.genpath(str(root)), nargout=0)
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
        eng = self._ensure_engine()
        try:
            # Real mode: mock=False -> runPipeline gates on cfg.model.available
            # and loads the trained model + calibration artifacts. Never the
            # mock MATLAB modules when this adapter is used.
            fieldnames = ["quality", "grading", "calibrated", "explain", "review", "report"]
            case_raw = eng.runPipeline(
                self._to_matlab_meta(metadata),
                str(image_path),
                "mock",
                False,
                nargout=1,
            )
            artifacts = _extract_explain_artifacts(case_raw)
            case = _to_py(case_raw)
        except RetinaSenseError:
            raise
        except Exception as exc:  # pragma: no cover - host-specific
            msg = str(exc)
            if "RetinaSense:runPipeline:MissingModel" in msg or "MissingModel" in msg:
                raise RetinaSenseError(
                    ErrorCode.MODEL_UNAVAILABLE,
                    "The trained model/calibration artifacts are missing. "
                    "Run scripts/benchmark_backbones.m + run_all_experiments.m on a "
                    "MATLAB host first.",
                    stage="matlab_adapter",
                )
            if "[ingestImage]" in msg or "ingestImage.m" in msg:
                raise RetinaSenseError(
                    ErrorCode.INVALID_IMAGE,
                    _ingest_error_message(msg),
                    stage="ingestImage",
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

        return self._map_case(case, artifacts)

    def _to_matlab_meta(self, metadata: dict[str, Any]) -> dict[str, Any]:
        """Build the MATLAB Case.meta struct (docs/ARCHITECTURE.md §4).

        The Case contract fixes meta fields patientId/eye/timestamp/phcId.
        Backend CaseMeta omits timestamp, so it is synthesized in ISO-8601
        (same shape MATLAB uses, e.g. datestr(now,'yyyy-mm-ddTHH:MM:SS')).
        """
        import datetime as _dt

        meta = {k: v for k, v in metadata.items() if k in ("patientId", "eye", "phcId")}
        meta.setdefault("timestamp", _dt.datetime.now().isoformat(timespec="seconds"))
        return meta

    def _map_case(
        self,
        case: dict[str, Any],
        artifacts: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Map the MATLAB Case onto the API adapter output shape.

        Only values actually present in the returned Case are used.  A missing
        field results in an explicit None/False — never an invented number.
        """
        artifacts = artifacts or {}
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
            # The real overlays are carried separately — they are persisted per
            # case by services.screening (which knows the case id) and exposed
            # as safe API references.  The availability flags are driven by the
            # actual image content extracted from the Case, never by the mere
            # presence of the parent field.
            result["explain"] = {
                "gradCamAvailable": artifacts.get("gradcam") is not None,
                "gradCamPath": None,
                "evidenceAvailable": artifacts.get("evidence") is not None,
                "evidencePath": None,
                "artifacts": artifacts,
                "note": explain.get("note"),
            }

        return result

    def stop(self) -> None:  # pragma: no cover - host-specific
        """Release the MATLAB engine if one was started."""
        if self._engine is not None:
            try:
                self._engine.quit()
            except Exception:
                pass
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

def _extract_explain_artifacts(case_raw: Any) -> dict[str, Any]:
    """Pull the real Grad-CAM / evidence overlay matrices out of the Case.

    The engine returns the 224x224x3 overlay arrays as matlab.uint8 values;
    they convert cleanly to numpy (verified against the live pipeline).  The
    arrays are returned separately so ``_to_py`` never has to materialise the
    images as nested Python lists, and so screening.py can persist them once it
    knows the case id.

    Content checks mirror services.artifacts: an all-zero attention overlay or
    a colourless evidence overlay is reported as ``None`` (honest absence),
    never a blank file.
    """
    from .artifacts import has_attention_content, has_visible_markers

    explain = _struct_get(case_raw, "explain")
    if not explain:
        return {"gradcam": None, "evidence": None}

    att = _as_uint8(_struct_get(explain, "attentionImage"))
    evi = _as_uint8(_struct_get(explain, "evidenceOverlay"))
    return {
        "gradcam": att if has_attention_content(att) else None,
        "evidence": evi if has_visible_markers(evi) else None,
    }


def _struct_get(obj: Any, name: str) -> Any:
    if obj is None:
        return None
    if isinstance(obj, dict):
        return obj.get(name)
    if hasattr(obj, "_fieldnames") and name in obj._fieldnames():
        return getattr(obj, name)
    return None


def _as_uint8(value: Any) -> np.ndarray | None:
    if value is None:
        return None
    try:
        if isinstance(value, np.ndarray):
            return np.asarray(value, dtype=np.uint8) if value.size else None
        size = value.size
        dims = tuple(size()) if callable(size) else tuple(size)
        if not dims or any(d == 0 for d in dims):
            return None
        return np.asarray(value, dtype=np.uint8)
    except Exception:  # pragma: no cover - host-specific engine behaviour
        return None


def _to_py(value: Any) -> Any:
    """Shallow-to-deep conversion from matlab.engine return values to python.

    matlab.* numeric arrays are indexed element-wise (iteration yields rows,
    so a flat float() loop silently drops/produces wrong vector shapes).
    Row/column vectors map to flat lists to keep the Case numeric contract;
    matrices map to nested row lists.
    """
    if hasattr(value, "_fieldnames"):  # matlab struct -> dict
        return {name: _to_py(getattr(value, name)) for name in value._fieldnames()}
    if isinstance(value, dict):        # nested python dict (sub-struct)
        return {k: _to_py(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_to_py(v) for v in value]
    if hasattr(value, "size") and not isinstance(value, (str, bytes)):
        # matlab.double / matlab.single / matlab.logical numeric array
        dims = tuple(value.size)
        if not dims or any(d == 0 for d in dims):
            return None
        if len(dims) == 1:
            return [_to_py(value[i]) for i in range(dims[0])]
        if dims[1] == 1:                       # column vector -> flat list
            return [_to_py(value[i][0]) for i in range(dims[0])]
        if dims[0] == 1:                       # row vector -> flat list
            return [_to_py(value[0][j]) for j in range(dims[1])]
        return [[_to_py(value[i][j]) for j in range(dims[1])] for i in range(dims[0])]
    return value


def _ingest_error_message(msg: str) -> str:
    """Extract the clean ingest-stage message from an engine exception dump.

    raiseError formats the MException as '[stage] msg'; the engine wrapper
    prepends MATLAB stack traces, so pull out the first '[ingestImage]' line.
    Falls back to the whole message (trimmed) if the marker is missing.
    """
    for line in msg.splitlines():
        line = line.strip()
        if line.startswith("[ingestImage]"):
            return line[len("[ingestImage]") :].strip()
    return msg.strip()


def _scalar(value: Any) -> float | None:
    if value is None or isinstance(value, str):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _scalar_int(value: Any) -> int | None:
    v = _scalar(value)
    return int(v) if v is not None else None


def _scalar_bool(value: Any) -> bool | None:
    v = _scalar(value)
    return bool(int(v)) if v is not None else None


def _vector(value: Any, length: int) -> list[float] | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        value = [value]
    try:
        items = [float(v) for v in value]
    except (TypeError, ValueError):
        return None
    if len(items) != length:
        return None
    return items