"""MatlabAdapter — bridge between the Python backend and the MATLAB RetinaSense pipeline.

Contract (docs/ARCHITECTURE.md §4):
    Backend -> MatlabAdapter -> runPipeline(case) -> Case result -> Backend JSON

When MATLAB Engine for Python is NOT available (the normal state on this dev
machine), the adapter raises MATLAB_ENGINE_UNAVAILABLE so the backend can
return a structured 503 — it never fabricates medical output.

A MockMatlabAdapter subclass is provided for tests; it returns deterministic
honest placeholder values and is CLEARLY LABELLED as TEST ONLY.
"""
from __future__ import annotations

import abc
from typing import Any

from ..config import MATLAB_ENGINE_AVAILABLE
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
    """Production adapter — calls MATLAB Engine for Python.

    Currently always raises MATLAB_ENGINE_UNAVAILABLE unless the engine
    is connected at startup (config.MATLAB_ENGINE_AVAILABLE).
    """

    def run_pipeline(
        self,
        image_path: str,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        if not MATLAB_ENGINE_AVAILABLE:
            raise RetinaSenseError(
                ErrorCode.MATLAB_ENGINE_UNAVAILABLE,
                "MATLAB Engine for Python is not available. "
                "Install MATLAB Runtime and enable it in config.",
                stage="matlab_adapter",
            )
        # Future implementation:
        # import matlab.engine
        # eng = matlab.engine.start_matlab()
        # ...
        raise RetinaSenseError(
            ErrorCode.MATLAB_ENGINE_UNAVAILABLE,
            "MATLAB Engine integration not yet implemented.",
            stage="matlab_adapter",
        )


class MockMatlabAdapter(BaseMatlabAdapter):
    """TEST-ONLY adapter.  Returns honest placeholder values.

    DO NOT use in production or inference paths.
    This exists solely to exercise the backend plumbing in tests.
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
