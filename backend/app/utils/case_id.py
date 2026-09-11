"""Opaque case-ID generator for RetinaSense.

Format: RS-2026-NNNNN  (sequential, zero-padded).
IDs are purely opaque — no patient information is encoded.
"""
from __future__ import annotations

import threading
from pathlib import Path

from ..config import CASE_ID_PREFIX, CASE_ID_WIDTH, CASES_DIR

_counter_lock = threading.Lock()
_counter: int | None = None


def _load_counter() -> int:
    """Scan existing case dirs to find the highest sequence number."""
    max_seq = 0
    if CASES_DIR.exists():
        for d in CASES_DIR.iterdir():
            if d.is_dir() and d.name.startswith(CASE_ID_PREFIX):
                try:
                    seq = int(d.name.split("-")[-1])
                    max_seq = max(max_seq, seq)
                except ValueError:
                    continue
    return max_seq


def next_case_id() -> str:
    """Return a fresh unique case ID. Thread-safe."""
    global _counter
    with _counter_lock:
        if _counter is None:
            _counter = _load_counter()
        _counter += 1
        return f"{CASE_ID_PREFIX}-{_counter:0{CASE_ID_WIDTH}d}"
