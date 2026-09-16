"""Authentication service — users, login, and token issuance.

Prototype-grade role-based auth on top of the SQLite users table
(db/models.UserRecord) and util/security primitives:

  * ``seed_users`` is idempotent and runs at startup (dev/demo-friendly).
  * ``authenticate(username, password)`` never reveals whether a username
    exists (generic error) and is constant-time on the hash comparison.
  * Tokens carry uid + role; ``require_roles`` (app/auth_deps.py) enforces
    per-route authorisation.
"""
from __future__ import annotations

from typing import Any

from ..config import SEED_USERS
from ..db.models import UserRecord
from ..db.session import session_scope
from ..utils.errors import ErrorCode, RetinaSenseError
from ..utils.security import create_token, hash_password, verify_password


def seed_users() -> None:
    """Create the configured seed accounts if they do not exist yet."""
    with session_scope() as s:
        for u in SEED_USERS:
            row = s.query(UserRecord).filter_by(username=u["username"]).one_or_none()
            if row is None:
                s.add(
                    UserRecord(
                        username=u["username"],
                        name=u["name"],
                        role=u["role"],
                        password_hash=hash_password(u["password"]),
                    )
                )


def username_to_name() -> dict[str, str]:
    """Map of username -> display name for every known account.

    Used by the reviewer-name backfill migration (legacy rows stored the
    username). Unknown users resolve to themselves.
    """
    with session_scope() as s:
        rows = s.query(UserRecord).all()
        return {row.username: row.name for row in rows}


def find_by_username(username: str) -> UserRecord | None:
    with session_scope() as s:
        return s.query(UserRecord).filter_by(username=username).one_or_none()


def find_by_id(user_id: int) -> UserRecord | None:
    with session_scope() as s:
        return s.query(UserRecord).filter_by(id=user_id).one_or_none()


def user_dict(user: UserRecord) -> dict[str, Any]:
    """Public (non-secret) representation of a user for API responses."""
    return {
        "id": user.id,
        "username": user.username,
        "name": user.name,
        "role": user.role,
    }


def authenticate(username: str, password: str) -> dict[str, Any]:
    """Verify credentials.  Raises UNAUTHORIZED on any mismatch."""
    user = find_by_username(username)
    if user is None or not verify_password(password, user.password_hash):
        raise RetinaSenseError(
            ErrorCode.UNAUTHORIZED,
            "Invalid username or password.",
            stage="auth",
        )
    return {
        "user": user_dict(user),
        "token": create_token(user.id, user.role),
    }