"""Database-store unit tests.

Verify the SQLite storage layer directly (independent of the HTTP API):
round-tripping records, the AI/final separation guardrail, image path safety,
and the case-ID sequence derived from the database.
"""
from __future__ import annotations

import io

import pytest

from app.services.matlab_adapter import MockMatlabAdapter
from app.services import screening as screening_svc
from app.storage import database_store
from app.utils.case_id import next_case_id


def _new_case_id() -> str:
    return next_case_id()


def test_metadata_roundtrip():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    database_store.save_metadata(case_id, {"patientId": "P-1", "eye": "OD", "phcId": "PHC-1"})
    assert database_store.load_metadata(case_id) == {"patientId": "P-1", "eye": "OD", "phcId": "PHC-1"}


def test_screening_roundtrip_preserves_shape():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    screening = {
        "status": "completed",
        "quality": {"class": "good", "score": 0.92, "failureReasons": []},
        "aiPrediction": {
            "grade": 1,
            "gradeLabel": "Mild NPDR",
            "referable": False,
            "confidence": 0.7,
            "uncertainty": 0.2,
            "reviewRequired": False,
        },
        "explainability": {
            "gradCamAvailable": False,
            "gradCamPath": None,
            "evidenceAvailable": False,
            "evidencePath": None,
        },
    }
    database_store.save_screening(case_id, screening)
    loaded = database_store.load_screening(case_id)
    assert loaded is not None
    assert loaded["status"] == "completed"
    assert loaded["quality"]["class"] == "good"
    assert loaded["aiPrediction"]["grade"] == 1


def test_review_does_not_touch_screening_row():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    database_store.save_screening(case_id, {
        "status": "completed",
        "quality": {"class": "good", "score": 0.9},
        "aiPrediction": {"grade": 2, "gradeLabel": "Moderate NPDR", "referable": True},
        "explainability": None,
    })
    database_store.save_review(case_id, {
        "review": {
            "action": "override",
            "reviewerId": "OPH-1",
            "overrideGrade": 3,
            "finalReferral": True,
            "status": "overridden",
            "notes": "",
        },
        "finalDecision": {"grade": 3, "gradeLabel": "Severe NPDR", "referral": True},
        "aiGradeImmutable": True,
    })

    # AI row unchanged; review + final decision stored separately.
    screening = database_store.load_screening(case_id)
    assert screening["aiPrediction"]["grade"] == 2

    review = database_store.load_review(case_id)
    assert review is not None
    assert review["review"]["overrideGrade"] == 3
    assert review["finalDecision"]["grade"] == 3
    assert review["aiGradeImmutable"] is True


def test_report_roundtrip():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    report = {"summary": "s", "disclaimer": "d", "payload": {"x": 1}}
    database_store.save_report(case_id, report)
    assert database_store.load_report(case_id) == report


def test_image_roundtrip_and_path_safety():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    path = database_store.save_image(case_id, "fundus.jpg", b"\xff\xd8\xff\xd9")
    assert path.is_file()
    assert database_store.load_image_path(case_id) == path
    records = database_store.load_image_records(case_id)
    assert len(records) == 1
    assert records[0]["filename"] == "fundus.jpg"
    assert records[0]["contentType"] == "image/jpeg"


def test_image_path_rejects_traversal():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    # Deliberately plant a record pointing outside DATA_DIR.
    from app.db.models import ImageRecord
    from app.db.session import session_scope

    with session_scope() as s:
        s.add(ImageRecord(
            case_id=case_id,
            filename="evil.jpg",
            relative_path="../../outside.jpg",
            content_type="image/jpeg",
            size_bytes=3,
        ))
    assert database_store.load_image_path(case_id) is None


def test_load_all_shape():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    assert database_store.load_all(case_id) == {
        "metadata": {"patientId": "", "eye": "", "phcId": ""},
        "screening": {},
        "review": None,
        "report": None,
    }


def test_create_case_dir_is_idempotent():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    database_store.create_case_dir(case_id)
    assert database_store.case_exists(case_id)


def test_case_id_sequence_derived_from_db():
    database_store.create_case_dir("RS-2026-00042")
    # Reset the in-process cache so it re-reads from the database.
    from app.utils import case_id as case_id_mod
    case_id_mod._counter = None
    assert next_case_id() == "RS-2026-00043"


def test_pipeline_persists_everything_to_db():
    case_id = _new_case_id()
    database_store.create_case_dir(case_id)
    database_store.save_metadata(case_id, {"patientId": "P-9", "eye": "OS", "phcId": "PHC-2"})

    adapter = MockMatlabAdapter(scenario="good")
    result = screening_svc.run_screening(
        case_id,
        io.BytesIO(b"\xff\xd8" + b"\x00" * 98),
        filename="test.jpg",
        content_type="image/jpeg",
        adapter=adapter,
    )
    assert result["status"] == "completed"
    assert database_store.load_screening(case_id) is not None
    assert database_store.load_image_path(case_id) is not None

    case_id2 = _new_case_id()
    database_store.create_case_dir(case_id2)
    adapter2 = MockMatlabAdapter(scenario="ungradable")
    result2 = screening_svc.run_screening(
        case_id2,
        io.BytesIO(b"\xff\xd8" + b"\x00" * 98),
        filename="dark.jpg",
        content_type="image/jpeg",
        adapter=adapter2,
    )
    assert result2["status"] == "recapture_required"
    assert database_store.load_screening(case_id2)["aiPrediction"] is None


def test_list_cases_orders_newest_first():
    ids = [_new_case_id() for _ in range(3)]
    for cid in ids:
        database_store.create_case_dir(cid)
    listed = database_store.list_cases()
    my_listed = [item["caseId"] for item in listed if item["caseId"] in ids]
    # ids are oldest->newest; list is newest first
    assert my_listed == list(reversed(ids))


def test_case_stats():
    stats = database_store.case_stats()
    assert isinstance(stats["totalCases"], int)
    assert isinstance(stats["screeningsCompleted"], int)
    assert isinstance(stats["pendingReviews"], int)