"""Structured error types for the RetinaSense backend.

Every API error returns a JSON body:
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable detail",
    "stage": "optional pipeline stage"
  }
}
HTTP status codes map 1:1 from error codes.
"""
from __future__ import annotations

from enum import Enum
from typing import Optional

from fastapi import HTTPException, status

# Version-tolerant status constants (older Starlette lacks the *_CONTENT_* names).
try:
    _HTTP_413_TOO_LARGE = status.HTTP_413_CONTENT_TOO_LARGE
except AttributeError:
    _HTTP_413_TOO_LARGE = status.HTTP_413_REQUEST_ENTITY_TOO_LARGE
try:
    _HTTP_422_UNPROCESSABLE = status.HTTP_422_UNPROCESSABLE_CONTENT
except AttributeError:
    _HTTP_422_UNPROCESSABLE = status.HTTP_422_UNPROCESSABLE_ENTITY


class ErrorCode(str, Enum):
    INVALID_IMAGE = "INVALID_IMAGE"
    UNSUPPORTED_FILE_TYPE = "UNSUPPORTED_FILE_TYPE"
    IMAGE_TOO_LARGE = "IMAGE_TOO_LARGE"
    UNGRADABLE_IMAGE = "UNGRADABLE_IMAGE"
    MODEL_UNAVAILABLE = "MODEL_UNAVAILABLE"
    MATLAB_ENGINE_UNAVAILABLE = "MATLAB_ENGINE_UNAVAILABLE"
    CASE_NOT_FOUND = "CASE_NOT_FOUND"
    INVALID_REVIEW = "INVALID_REVIEW"
    REPORT_UNAVAILABLE = "REPORT_UNAVAILABLE"
    IMAGE_UNAVAILABLE = "IMAGE_UNAVAILABLE"
    UNAUTHORIZED = "UNAUTHORIZED"
    FORBIDDEN = "FORBIDDEN"
    INTERNAL_ERROR = "INTERNAL_ERROR"


_ERROR_STATUS_MAP: dict[ErrorCode, int] = {
    ErrorCode.INVALID_IMAGE: status.HTTP_400_BAD_REQUEST,
    ErrorCode.UNSUPPORTED_FILE_TYPE: status.HTTP_400_BAD_REQUEST,
    ErrorCode.IMAGE_TOO_LARGE: _HTTP_413_TOO_LARGE,
    ErrorCode.UNGRADABLE_IMAGE: _HTTP_422_UNPROCESSABLE,
    ErrorCode.MODEL_UNAVAILABLE: status.HTTP_503_SERVICE_UNAVAILABLE,
    ErrorCode.MATLAB_ENGINE_UNAVAILABLE: status.HTTP_503_SERVICE_UNAVAILABLE,
    ErrorCode.CASE_NOT_FOUND: status.HTTP_404_NOT_FOUND,
    ErrorCode.INVALID_REVIEW: status.HTTP_400_BAD_REQUEST,
    ErrorCode.REPORT_UNAVAILABLE: status.HTTP_404_NOT_FOUND,
    ErrorCode.IMAGE_UNAVAILABLE: status.HTTP_404_NOT_FOUND,
    ErrorCode.UNAUTHORIZED: status.HTTP_401_UNAUTHORIZED,
    ErrorCode.FORBIDDEN: status.HTTP_403_FORBIDDEN,
    ErrorCode.INTERNAL_ERROR: status.HTTP_500_INTERNAL_SERVER_ERROR,
}


class RetinaSenseError(HTTPException):
    """Application-specific error that serialises to the standard JSON shape."""

    def __init__(
        self,
        code: ErrorCode,
        message: str,
        stage: Optional[str] = None,
    ):
        self.error_code = code
        self.stage = stage
        detail = {"error": {"code": code.value, "message": message}}
        if stage:
            detail["error"]["stage"] = stage
        super().__init__(_ERROR_STATUS_MAP[code], detail=detail)
