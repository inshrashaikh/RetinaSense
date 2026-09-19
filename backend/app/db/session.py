"""SQLAlchemy engine / session helpers for the RetinaSense database.

By default the database is a SQLite file at config.DATABASE_PATH
(backend/data/retinasense.db); set config.DATABASE_URL
(RETINASENSE_DATABASE_URL) to use an external engine instead (e.g. Postgres
in the docker-compose stack). Tests point it at a temp dir.
"""
from __future__ import annotations

import os
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


def configure_database(
    path: Optional[Path] = None,
    url: Optional[str] = None,
) -> None:
    """Point the app at a database and prepare a session factory.

    Resolution order:
      1. `url` argument (tests / external callers).
      2. ``RETINASENSE_DATABASE_URL`` env var — an external engine such as
         Postgres in the docker-compose stack.
      3. `path` argument, else config.DATABASE_PATH — the SQLite fallback.

    SQLite gets per-connection tweaks (thread flag + FK pragma); external
    engines are used as configured. Safe to call more than once (replaces the
    engine and session factory).
    """
    global _engine, _SessionLocal

    connect_url = url or os.environ.get("RETINASENSE_DATABASE_URL")
    if connect_url is None:
        from ..config import DATABASE_PATH

        db_path = Path(path) if path is not None else DATABASE_PATH
        db_path.parent.mkdir(parents=True, exist_ok=True)
        connect_url = _sqlite_url(db_path)

    engine_kwargs: dict = {"pool_pre_ping": True}
    if connect_url.startswith("sqlite"):
        engine_kwargs["connect_args"] = {"check_same_thread": False}

    is_sqlite = connect_url.startswith("sqlite")
    _engine = create_engine(connect_url, **engine_kwargs)
    if is_sqlite:
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