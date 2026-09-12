"""Opaque case-ID generator for RetinaSense.

Format: RS-2026-NNNNN  (sequential, zero-padded).
IDs are purely opaque — no patient information is encoded.
"""
from __future__ import annotations

import threading

from ..config import CASE_ID_PREFIX, CASE_ID_WIDTH

_counter_lock = threading.Lock()
_counter: int | None = None


def _load_counter() -> int:
    """Scan the database for the highest existing sequence number."""
    from ..storage import database_store
    return database_store.max_case_sequence(CASE_ID_PREFIX)


def next_case_id() -> str:
    """Return a fresh unique case ID. Thread-safe."""
    global _counter
    with _counter_lock:
        if _counter is None:
            _counter = _load_counter()
        _counter += 1
        return f"{CASE_ID_PREFIX}-{_counter:0{CASE_ID_WIDTH}d}"
