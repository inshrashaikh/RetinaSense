"""SQLAlchemy engine / session helpers for the RetinaSense database.

The database file lives at config.DATABASE_PATH (backend/data/retinasense.db)
unless configured otherwise (tests point it at a temp dir).
"""
from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from typing import Generator, Optional

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

_engine: Optional[Engine] = None
_SessionLocal: Optional[sessionmaker] = None


def _sqlite_url(path: Path) -> str:
    """Build a SQLite URL that works for absolute Windows/Unix paths."""
    return f"sqlite:///{path.as_posix()}"


def _set_sqlite_pragma(dbapi_connection, connection_record) -> None:
    """Enable foreign-key enforcement for SQLite (off by default)."""
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


def configure_database(path: Optional[Path] = None) -> None:
    """Point the app at a SQLite database file and prepare a session factory.

    Safe to call more than once (replaces the engine and session factory).
    """
    global _engine, _SessionLocal
    from ..config import DATABASE_PATH

    db_path = Path(path) if path is not None else DATABASE_PATH
    db_path.parent.mkdir(parents=True, exist_ok=True)

    _engine = create_engine(
        _sqlite_url(db_path),
        connect_args={"check_same_thread": False},
        pool_pre_ping=True,
    )
    event.listen(_engine, "connect", _set_sqlite_pragma)
    _SessionLocal = sessionmaker(bind=_engine, autoflush=False, expire_on_commit=False)


def init_db() -> None:
    """Create all tables if they do not exist yet."""
    if _engine is None:
        raise RuntimeError("RetinaSense db: configure_database() must be called before init_db().")
    from . import models  # noqa: F401  (registers the models on Base)

    models.Base.metadata.create_all(_engine)


@contextmanager
def session_scope() -> Generator[Session, None, None]:
    """Context manager yielding a Session that commits on success, rolls back
    on error, and always closes."""
    if _SessionLocal is None:
        raise RuntimeError("RetinaSense db: configure_database() must be called before use.")
    session = _SessionLocal()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()