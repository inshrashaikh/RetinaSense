"""Comprehensive tests for the RetinaSense backend.

16 test cases covering:
1.  Health check
2.  Case creation
3.  Case retrieval
4.  Invalid image upload
5.  Unsupported file type
6.  Oversized file
7.  MATLAB unavailable state
8.  Ungradable state
9.  Successful structured result (test adapter)
10. Human approve
11. Human override
12. Recapture
13. AI prediction remains immutable after override
14. Final referral decision
15. Case-not-found
16. No fabricated medical output
"""
from __future__ import annotations

import io
import json

import pytest
from fastapi.testclient import TestClient

import app.config as cfg
from app.main import app
from app.models.schemas import CreateCaseResponse
from app.services.matlab_adapter import MockMatlabAdapter
from app.services import screening as screening_svc
from app.storage import local_store
from app.utils.case_id import next_case_id


client = TestClient(app, raise_server_exceptions=False)


# ─── helpers ───────────────────────────────────────────────────────────────

def _create_case() -> str:
    """Create a case via the API and return its ID."""
    resp = client.post("/api/cases", data={"patientId": "TEST-001", "eye": "left", "phcId": "PHC-1"})
    assert resp.status_code == 201
    return resp.json()["caseId"]


def _upload_image(case_id: str, *, filename="test.jpg", content_type="image/jpeg", size=100) -> dict:
    """Upload an image for screening using the test adapter (good scenario)."""
    img_data = b"\xff\xd8" + b"\x00" * (size - 2) if size >= 2 else b"\xff"
    adapter = MockMatlabAdapter(scenario="good")
    result = screening_svc.run_screening(
        case_id,
        io.BytesIO(img_data),
        filename=filename,
        content_type=content_type,
        adapter=adapter,
    )
    return result


# ─── 1. Health check ──────────────────────────────────────────────────────

def test_health():
    resp = client.get("/api/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["matlabEngine"] is False
    assert "version" in body


# ─── 2. Case creation ─────────────────────────────────────────────────────

def test_create_case():
    resp = client.post("/api/cases", data={"patientId": "P-100", "eye": "right", "phcId": "PHC-9"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["caseId"].startswith("RS-2026-")
    assert body["status"] == "created"
    # Verify case dir was created
    assert (cfg.CASES_DIR / body["caseId"]).exists()


# ─── 3. Case retrieval ────────────────────────────────────────────────────

def test_get_case():
    case_id = _create_case()
    # Upload an image so the case has screening data
    _upload_image(case_id)

    resp = client.get(f"/api/cases/{case_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["caseId"] == case_id
    assert "quality" in body
    assert "aiPrediction" in body
    assert "explainability" in body


# ─── 4. Invalid image upload (0 bytes) ───────────────────────────────────

def test_invalid_image_upload():
    case_id = _create_case()
    resp = client.post(
        f"/api/cases/{case_id}/screen",
        files={"image": ("empty.jpg", b"", "image/jpeg")},
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "INVALID_IMAGE"


# ─── 5. Unsupported file type ─────────────────────────────────────────────

def test_unsupported_file_type():
    case_id = _create_case()
    resp = client.post(
        f"/api/cases/{case_id}/screen",
        files={"image": ("scan.bmp", b"BM" + b"\x00" * 50, "image/bmp")},
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "UNSUPPORTED_FILE_TYPE"


# ─── 6. Oversized file ───────────────────────────────────────────────────

def test_oversized_file():
    case_id = _create_case()
    # 21 MB > 20 MB limit
    big_data = b"\xff\xd8" + b"\x00" * (21 * 1024 * 1024)
    resp = client.post(
        f"/api/cases/{case_id}/screen",
        files={"image": ("big.jpg", big_data, "image/jpeg")},
    )
    assert resp.status_code == 413
    assert resp.json()["error"]["code"] == "IMAGE_TOO_LARGE"


# ─── 7. MATLAB unavailable state ─────────────────────────────────────────

def test_matlab_unavailable():
    from app.services.matlab_adapter import MatlabAdapter
    from app.utils.errors import RetinaSenseError, ErrorCode

    adapter = MatlabAdapter()
    with pytest.raises(RetinaSenseError) as exc_info:
        adapter.run_pipeline("/tmp/fake.jpg", {})
    assert exc_info.value.error_code == ErrorCode.MATLAB_ENGINE_UNAVAILABLE


# ─── 8. Ungradable state ─────────────────────────────────────────────────

def test_ungradable_state():
    case_id = _create_case()
    adapter = MockMatlabAdapter(scenario="ungradable")
    img_data = b"\xff\xd8" + b"\x00" * 98
    result = screening_svc.run_screening(
        case_id,
        io.BytesIO(img_data),
        filename="dark.jpg",
        content_type="image/jpeg",
        adapter=adapter,
    )
    assert result["status"] == "recapture_required"
    assert result["quality"]["class"] == "ungradable"
    assert result["aiPrediction"] is None

    # Verify via GET
    resp = client.get(f"/api/cases/{case_id}")
    assert resp.status_code == 200
    assert resp.json()["status"] == "recapture_required"
    assert resp.json()["quality"]["class"] == "ungradable"


# ─── 9. Successful structured result (test adapter) ──────────────────────

def test_successful_screening():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.get(f"/api/cases/{case_id}")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "completed"
    assert body["quality"]["class"] == "good"
    assert body["aiPrediction"]["grade"] == 0
    assert body["aiPrediction"]["gradeLabel"] == "No DR"
    assert body["aiPrediction"]["referable"] is False
    assert body["aiPrediction"]["confidence"] is not None
    assert body["aiPrediction"]["uncertainty"] is not None


# ─── 10. Human approve ───────────────────────────────────────────────────

def test_human_approve():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.post(
        f"/api/cases/{case_id}/review",
        json={
            "action": "approve",
            "reviewerId": "OPH-1",
            "notes": "Looks good.",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["review"]["action"] == "approve"
    assert body["review"]["status"] == "approved"
    assert body["finalDecision"]["referral"] is False


# ─── 11. Human override ──────────────────────────────────────────────────

def test_human_override():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.post(
        f"/api/cases/{caseId}" if False else f"/api/cases/{case_id}/review",
        json={
            "action": "override",
            "reviewerId": "OPH-2",
            "overrideGrade": 2,
            "notes": "Moderate NPDR seen.",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["review"]["action"] == "override"
    assert body["review"]["overrideGrade"] == 2
    assert body["finalDecision"]["grade"] == 2
    assert body["finalDecision"]["referral"] is True


# ─── 12. Recapture ───────────────────────────────────────────────────────

def test_recapture():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.post(
        f"/api/cases/{case_id}/review",
        json={
            "action": "recapture",
            "reviewerId": "OPH-1",
            "notes": "Image too blurry.",
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["review"]["action"] == "recapture"
    assert body["review"]["status"] == "recapture"
    assert body["finalDecision"]["grade"] is None
    assert body["finalDecision"]["referral"] is False


# ─── 13. AI prediction remains immutable after override ───────────────────

def test_ai_immutable_after_override():
    case_id = _create_case()
    _upload_image(case_id)

    # Read original AI grade
    screening_before = local_store.load_screening(case_id)
    original_grade = screening_before["aiPrediction"]["grade"]
    assert original_grade == 0

    # Override to grade 3
    client.post(
        f"/api/cases/{case_id}/review",
        json={
            "action": "override",
            "reviewerId": "OPH-3",
            "overrideGrade": 3,
            "notes": "Severe NPDR observed.",
        },
    )

    # AI prediction must NOT have changed
    screening_after = local_store.load_screening(case_id)
    assert screening_after["aiPrediction"]["grade"] == original_grade
    assert screening_after["aiPrediction"]["grade"] == 0

    # The review data stores the override separately
    review_data = local_store.load_review(case_id)
    assert review_data["review"]["overrideGrade"] == 3
    assert review_data["finalDecision"]["grade"] == 3
    assert review_data["aiGradeImmutable"] is True


# ─── 14. Final referral decision ──────────────────────────────────────────

def test_final_referral_decision():
    case_id = _create_case()
    _upload_image(case_id)

    # Override to grade 3 (referable)
    resp = client.post(
        f"/api/cases/{case_id}/review",
        json={
            "action": "override",
            "reviewerId": "OPH-4",
            "overrideGrade": 3,
            "notes": "",
        },
    )
    body = resp.json()
    assert body["finalDecision"]["referral"] is True

    # Approve keeps AI grade (non-referable) => no referral
    case_id2 = _create_case()
    _upload_image(case_id2)
    resp2 = client.post(
        f"/api/cases/{case_id2}/review",
        json={
            "action": "approve",
            "reviewerId": "OPH-5",
            "notes": "",
        },
    )
    body2 = resp2.json()
    assert body2["finalDecision"]["referral"] is False


# ─── 15. Case-not-found ──────────────────────────────────────────────────

def test_case_not_found():
    resp = client.get("/api/cases/RS-2026-99999")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "CASE_NOT_FOUND"


# ─── 16. No fabricated medical output ─────────────────────────────────────

def test_no_fabricated_medical_output():
    """When MATLAB is unavailable, the backend never returns fake grades."""
    case_id = _create_case()
    # Do NOT run screening — no adapter was called

    resp = client.get(f"/api/cases/{case_id}")
    assert resp.status_code == 200
    body = resp.json()

    # AI prediction fields must all be null (not fabricated)
    assert body["aiPrediction"]["grade"] is None
    assert body["aiPrediction"]["gradeLabel"] is None
    assert body["aiPrediction"]["referable"] is None
    assert body["aiPrediction"]["confidence"] is None
    assert body["aiPrediction"]["uncertainty"] is None

    # Quality fields also null (no screening performed)
    assert body["quality"]["class"] is None
    assert body["quality"]["score"] is None


# ─── Extra: invalid review action ─────────────────────────────────────────

def test_invalid_review_action():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.post(
        f"/api/cases/{case_id}/review",
        json={
            "action": "invalid_action",
            "reviewerId": "OPH-1",
        },
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "INVALID_REVIEW"


# ─── Extra: override without grade ────────────────────────────────────────

def test_override_without_grade():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.post(
        f"/api/cases/{case_id}/review",
        json={
            "action": "override",
            "reviewerId": "OPH-1",
        },
    )
    assert resp.status_code == 400
    assert resp.json()["error"]["code"] == "INVALID_REVIEW"
