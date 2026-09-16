"""FastAPI auth dependencies: get_current_user + require_roles.

Every route that touches case / screening / review / report data requires an
authenticated user (Authorization: Bearer <token>). Route roles map to the
three RetinaSense actors (docs/ARCHITECTURE.md §1, PRD §3):

  * phc_operator      - captures images, runs screenings, uploads images
  * ophthalmologist   - reviews AI output and issues final decisions
  * admin             - district-wide oversight (stats, all endpoints)
"""
from __future__ import annotations

from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .db.models import UserRecord
from .services import auth as auth_svc
from .utils.errors import ErrorCode, RetinaSenseError
from .utils.security import decode_token

_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> UserRecord:
    """Resolve the authenticated user from the bearer token."""
    if credentials is None or not credentials.credentials:
        raise RetinaSenseError(
            ErrorCode.UNAUTHORIZED,
            "Authentication required. Provide an Authorization: Bearer <token> header.",
            stage="auth",
        )
    payload = decode_token(credentials.credentials)
    if payload is None:
        raise RetinaSenseError(
            ErrorCode.UNAUTHORIZED,
            "Invalid or expired token.",
            stage="auth",
        )
    user = auth_svc.find_by_id(int(payload["uid"]))
    if user is None:
        raise RetinaSenseError(
            ErrorCode.UNAUTHORIZED,
            "The account for this token no longer exists.",
            stage="auth",
        )
    return user


def require_roles(*roles: str):
    """Dependency factory that only allows the given roles through."""
    allowed = set(roles)

    def _check(user: Annotated[UserRecord, Depends(get_current_user)]) -> UserRecord:
        if user.role not in allowed:
            raise RetinaSenseError(
                ErrorCode.FORBIDDEN,
                f"Role '{user.role}' is not allowed for this operation. "
                f"Requires one of: {', '.join(sorted(allowed))}.",
                stage="auth",
            )
        return user

    return _check


CurrentUser = Annotated[UserRecord, Depends(get_current_user)]