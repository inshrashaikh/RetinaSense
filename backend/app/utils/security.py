"""Security primitives for RetinaSense authentication.

Prototype-grade but real auth built on the Python stdlib only:

  * Passwords: PBKDF2-HMAC-SHA256 with a per-user random salt and a
    configurable iteration count (OWASP-style).
  * Tokens: HMAC-SHA256 signed bearer tokens carrying {user_id, role, exp}
    (base64url payload, hex signature). No external JWT dependency.

NO secrets are committed anywhere - the signing secret comes from the
environment (RETINASENSE_TOKEN_SECRET) with a dev-only fallback that is
warned about at startup (see app/main.py).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from typing import Any

from ..config import (
    TOKEN_EXPIRY_HOURS,
    TOKEN_SECRET,
)

_PBKDF2_ITERATIONS = 240_000


# ---------------------------------------------------------------------------
# Password hashing
# ---------------------------------------------------------------------------

def hash_password(password: str) -> str:
    """Return a stored format 'pbkdf2$iterations$salt$digest'."""
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, _PBKDF2_ITERATIONS
    )
    return "$".join(
        [
            "pbkdf2",
            str(_PBKDF2_ITERATIONS),
            base64.urlsafe_b64encode(salt).decode("ascii"),
            base64.urlsafe_b64encode(digest).decode("ascii"),
        ]
    )


def verify_password(password: str, stored: str) -> bool:
    """Verify *password* against a 'pbkdf2$it$salt$digest' string."""
    try:
        algorithm, iterations, salt_b64, digest_b64 = stored.split("$")
        if algorithm != "pbkdf2":
            return False
        salt = base64.urlsafe_b64decode(salt_b64.encode("ascii"))
        expected = base64.urlsafe_b64decode(digest_b64.encode("ascii"))
        actual = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            salt,
            int(iterations),
        )
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


# ---------------------------------------------------------------------------
# Signed bearer tokens (HMAC-SHA256)
# ---------------------------------------------------------------------------

def _b64encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _b64decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode((data + padding).encode("ascii"))


def _sign(payload_b64: str) -> str:
    return hmac.new(
        TOKEN_SECRET.encode("utf-8"), payload_b64.encode("ascii"), hashlib.sha256
    ).hexdigest()


def create_token(user_id: int, role: str, *, expiry_hours: float | None = None) -> str:
    """Create an HMAC-signed bearer token for a user."""
    exp = time.time() + (expiry_hours or TOKEN_EXPIRY_HOURS) * 3600
    payload = {"uid": user_id, "role": role, "exp": exp}
    payload_b64 = _b64encode(json.dumps(payload).encode("utf-8"))
    return f"{payload_b64}.{_sign(payload_b64)}"


def decode_token(token: str) -> dict[str, Any] | None:
    """Verify signature + expiry and return the payload, or None."""
    try:
        payload_b64, signature = token.split(".", 1)
    except ValueError:
        return None
    if not hmac.compare_digest(_sign(payload_b64), signature):
        return None
    try:
        payload = json.loads(_b64decode(payload_b64))
    except (ValueError, TypeError):
        return None
    if payload.get("exp", 0) < time.time():
        return None
    return payload


def generate_secret() -> str:
    """Random 32-byte secret for local dev environments."""
    return secrets.token_hex(32)