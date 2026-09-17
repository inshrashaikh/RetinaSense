"""Test configuration — uses a temporary data directory per session."""
from __future__ import annotations

import shutil

import pytest
from fastapi.testclient import TestClient

import app.config as cfg
from app.main import app
from app.services.matlab_adapter import MockMatlabAdapter


@pytest.fixture(autouse=True, scope="session")
def _temp_data_dir(tmp_path_factory):
    """Redirect all storage to a temp directory for the test session."""
    tmp = tmp_path_factory.mktemp("test_data")
    cases_dir = tmp / "cases"
    images_dir = tmp / "images"
    db_path = tmp / "retinasense.db"
    cases_dir.mkdir(parents=True, exist_ok=True)
    images_dir.mkdir(parents=True, exist_ok=True)

    # config values are bound by value at import time in local_store/case_id —
    # patch the module-level attributes so tests never touch real data/.
    cfg.CASES_DIR = cases_dir
    cfg.IMAGES_DIR = images_dir
    cfg.DATABASE_PATH = db_path
    cfg.ARTIFACTS_DIR = tmp / "artifacts"
    cfg.REPORTS_DIR = tmp / "reports"
    cfg.ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    cfg.REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    import app.storage.local_store as local_store
    import app.storage.database_store as database_store
    import app.utils.case_id as case_id_mod
    local_store.CASES_DIR = cases_dir
    local_store.IMAGES_DIR = images_dir
    database_store.DATA_DIR = tmp
    case_id_mod._counter = None  # restart ID counter over the temp database
    # artifacts/pdf_report captured the dirs by value at import time, so the
    # redirection must be patched on those modules too.
    import app.services.artifacts as artifacts_svc
    import app.services.pdf_report as pdf_report_svc
    artifacts_svc.ARTIFACTS_DIR = cfg.ARTIFACTS_DIR
    pdf_report_svc.REPORTS_DIR = cfg.REPORTS_DIR
    pdf_report_svc._ARTIFACTS_DIR = cfg.ARTIFACTS_DIR

    from app.db.session import configure_database, init_db

    configure_database(db_path)
    init_db()

    # Seed the demo accounts so authenticated API tests can log in
    # (in production this happens in app.main.lifespan).
    from app.services import auth as auth_svc

    auth_svc.seed_users()

    yield tmp
    shutil.rmtree(tmp, ignore_errors=True)


@pytest.fixture()
def client():
    """FastAPI test client."""
    return TestClient(app, raise_server_exceptions=False)


@pytest.fixture()
def test_adapter_good():
    return MockMatlabAdapter(scenario="good")


@pytest.fixture()
def test_adapter_ungradable():
    return MockMatlabAdapter(scenario="ungradable")


@pytest.fixture()
def dummy_jpg_bytes() -> bytes:
    """Minimal valid JPEG bytes (SOI + EOI markers)."""
    return b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"


@pytest.fixture()
def dummy_png_bytes() -> bytes:
    """Minimal valid 1x1 red PNG."""
    import struct, zlib
    def _chunk(ctype: bytes, data: bytes) -> bytes:
        c = ctype + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    raw = zlib.compress(b"\x00\xff\x00\x00")
    png = b"\x89PNG\r\n\x1a\n"
    png += _chunk(b"IHDR", ihdr)
    png += _chunk(b"IDAT", raw)
    png += _chunk(b"IEND", b"")
    return png
