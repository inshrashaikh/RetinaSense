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
from app.storage import database_store
from app.utils.case_id import next_case_id


client = TestClient(app, raise_server_exceptions=False)


@pytest.fixture(scope="module", autouse=True)
def _authenticated_client():
    """Attach a bearer token to the module-level client.

    The seed accounts are created by the session-scoped ``_temp_data_dir``
    fixture (see conftest.py); every case/screening/review/report endpoint
    requires an authenticated user, so the whole module logs in once.
    """
    resp = client.post("/api/auth/login", json={"username": "doctor", "password": "doctor123"})
    assert resp.status_code == 200, resp.text
    token = resp.json()["token"]
    client.headers.update({"Authorization": f"Bearer {token}"})
    yield


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
    # Host-dependent: True when matlab.engine is installed (R2026a dev box),
    # False on CI hosts without the engine package.
    assert body["matlabEngine"] is cfg.MATLAB_ENGINE_AVAILABLE
    assert "version" in body


# ─── 2. Case creation ─────────────────────────────────────────────────────

def test_create_case():
    resp = client.post("/api/cases", data={"patientId": "P-100", "eye": "right", "phcId": "PHC-9"})
    assert resp.status_code == 201
    body = resp.json()
    assert body["caseId"].startswith("RS-2026-")
    assert body["status"] == "created"
    # Verify the case was registered in the database
    assert database_store.case_exists(body["caseId"])


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

def test_matlab_unavailable(monkeypatch):
    from app.services.matlab_adapter import MatlabAdapter
    from app.utils.errors import RetinaSenseError, ErrorCode

    # Force the "MATLAB not available" state regardless of the host, so the
    # test is deterministic on CI machines without the engine AND on the R2026a
    # dev box where the engine is importable.
    import app.services.matlab_adapter as matlab_adapter

    monkeypatch.setattr(matlab_adapter, "MATLAB_ENGINE_AVAILABLE", False)

    adapter = MatlabAdapter()
    with pytest.raises(RetinaSenseError) as exc_info:
        adapter.run_pipeline("/tmp/fake.jpg", {})
    assert exc_info.value.error_code == ErrorCode.MATLAB_ENGINE_UNAVAILABLE


# ─── 7b. Screen route -> structured 503 when MATLAB is not available ─────

def test_screen_route_pipeline_unavailable(monkeypatch):
    """The default (real) adapter must FAIL the screening with a structured
    503 — never fabricate a grade when MATLAB is missing.

    Patches both SIMULATION_MODE (to 'off' so the real MatlabAdapter path is
    exercised even when backend/.env sets RETINASENSE_SIMULATION=mock) and
    MATLAB_ENGINE_AVAILABLE (to False so it raises 503 without MATLAB).
    """
    import app.services.matlab_adapter as matlab_adapter
    import app.config as config_mod

    monkeypatch.setattr(config_mod, "SIMULATION_MODE", "off")
    monkeypatch.setattr(matlab_adapter, "MATLAB_ENGINE_AVAILABLE", False)
    case_id = _create_case()
    resp = client.post(
        f"/api/cases/{case_id}/screen",
        files={"image": ("fundus.jpg", b"\xff\xd8" + b"\x00" * 98, "image/jpeg")},
    )
    assert resp.status_code == 503
    body = resp.json()["error"]
    assert body["code"] == "MATLAB_ENGINE_UNAVAILABLE"


# ─── 7c. Simulation mode drives the labelled mock adapter ────────────────

def test_simulation_mode_screens_end_to_end(monkeypatch):
    """RETINASENSE_SIMULATION=mock -> default adapter is the labelled mock, so
    the FULL /case -> /screen -> /case flow works without MATLAB."""
    monkeypatch.setattr(cfg, "SIMULATION_MODE", "mock")
    case_id = _create_case()
    resp = client.post(
        f"/api/cases/{case_id}/screen",
        files={"image": ("fundus.jpg", b"\xff\xd8" + b"\x00" * 98, "image/jpeg")},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "completed"
    assert body["quality"]["class"] == "good"
    assert body["aiPrediction"]["grade"] == 0
    # The mock is honest: no explainability is claimed.
    assert body["explainability"]["gradCamAvailable"] is False

    get_resp = client.get(f"/api/cases/{case_id}")
    assert get_resp.status_code == 200
    assert get_resp.json()["status"] == "completed"


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


def test_screen_route_returns_enhancement_recapture(monkeypatch):
    """A real enhancement recheck may retain class=borderline but request recapture."""
    class EnhancementRecaptureAdapter:
        def run_pipeline(self, image_path, metadata):
            return {
                "quality": {
                    "class": "borderline",
                    "score": 0.45,
                    "failureReasons": ["focus"],
                    "recaptureReason": "LOW_FOCUS",
                    "recaptureInstruction": "Please recapture with better focus.",
                },
                "grading": None,
                "calibrated": None,
                "explain": None,
                "review": None,
            }

    import app.services.matlab_adapter as matlab_adapter

    monkeypatch.setattr(
        matlab_adapter,
        "default_adapter",
        lambda: EnhancementRecaptureAdapter(),
    )
    case_id = _create_case()
    resp = client.post(
        f"/api/cases/{case_id}/screen",
        files={"image": ("blurred.jpg", b"\xff\xd8" + b"\x00" * 98, "image/jpeg")},
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "recapture_required"
    assert body["quality"]["class"] == "borderline"
    assert body["quality"]["recaptureReason"] == "LOW_FOCUS"
    assert body["quality"]["recaptureInstruction"] == "Please recapture with better focus."
    assert body["aiPrediction"]["grade"] is None


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
    # The authenticated user signs the review with their DISPLAY name, not the
    # (discarded) body.reviewerId.
    assert body["review"]["reviewerId"] == "Dr. Meera Rao"
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
    screening_before = database_store.load_screening(case_id)
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
    screening_after = database_store.load_screening(case_id)
    assert screening_after["aiPrediction"]["grade"] == original_grade
    assert screening_after["aiPrediction"]["grade"] == 0

    # The review data stores the override separately
    review_data = database_store.load_review(case_id)
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


# ─── 17. Case list endpoint ───────────────────────────────────────────────

def test_list_cases():
    case_id = _create_case()
    resp = client.get("/api/cases")
    assert resp.status_code == 200
    items = resp.json()
    assert isinstance(items, list)
    assert any(item["caseId"] == case_id for item in items)
    entry = next(item for item in items if item["caseId"] == case_id)
    assert entry["status"] == "created"
    assert entry["patientId"] == "TEST-001"


# ─── 18. Case image endpoint ──────────────────────────────────────────────

def test_case_image_available():
    case_id = _create_case()
    _upload_image(case_id)
    resp = client.get(f"/api/cases/{case_id}/image")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("image/jpeg")
    assert resp.content


def test_case_image_unavailable():
    case_id = _create_case()
    resp = client.get(f"/api/cases/{case_id}/image")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "IMAGE_UNAVAILABLE"


def test_case_image_not_found():
    resp = client.get("/api/cases/RS-2026-99999/image")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "CASE_NOT_FOUND"


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


# ─── 19. Case stats endpoint ──────────────────────────────────────────────

def test_case_stats_empty():
    resp = client.get("/api/cases/stats")
    assert resp.status_code == 200
    body = resp.json()
    assert body["totalCases"] >= 0
    assert body["screeningsCompleted"] >= 0
    assert body["pendingReviews"] >= 0
    assert isinstance(body["totalCases"], int)


def test_case_stats_after_creation_and_screening():
    case_id = _create_case()
    _upload_image(case_id)
    resp = client.get("/api/cases/stats")
    assert resp.status_code == 200
    body = resp.json()
    assert body["totalCases"] >= 1
    assert body["screeningsCompleted"] >= 1


# ─── 20. CORS headers ────────────────────────────────────────────────────
# The API authenticates with bearer tokens (never cookies), so CORS defaults
# to allow ANY origin (`config.CORS_ORIGINS == ["*"]`); an explicit
# `RETINASENSE_CORS_ORIGINS` env can still pin the allow-list.

def test_cors_allows_any_origin_by_default():
    resp = client.options(
        "/api/health",
        headers={
            "Origin": "http://localhost:5173",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert resp.status_code == 200
    assert resp.headers.get("access-control-allow-origin") == "*"


def test_cors_allows_arbitrary_origin_by_default():
    resp = client.options(
        "/api/health",
        headers={
            "Origin": "http://192.168.137.1:5173",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert resp.status_code == 200
    assert resp.headers.get("access-control-allow-origin") == "*"


# ─── 21. Report generation ────────────────────────────────────────────────

def test_report_generation_after_screening():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.post(f"/api/cases/{case_id}/report")
    assert resp.status_code == 200
    body = resp.json()
    assert body["caseId"] == case_id
    assert body["report"] is not None
    assert body["report"]["quality"]["class"] == "good"
    assert body["summary"] is not None
    assert "Screening decision-support" in body["disclaimer"]

    # Verify it can be retrieved via GET
    resp2 = client.get(f"/api/cases/{case_id}/report")
    assert resp2.status_code == 200
    assert resp2.json()["report"]["quality"]["class"] == "good"


def test_report_generation_without_screening():
    case_id = _create_case()
    resp = client.post(f"/api/cases/{case_id}/report")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "REPORT_UNAVAILABLE"


def test_report_generation_not_found():
    resp = client.post("/api/cases/RS-2026-99999/report")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "CASE_NOT_FOUND"


# ─── 22. Health includes database status ──────────────────────────────────

def test_health_database_field():
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.json()["database"] == "ok"


# ─── 23. Report after review shows both ──────────────────────────────────

def test_report_after_override_shows_both_grades():
    case_id = _create_case()
    _upload_image(case_id)
    client.post(
        f"/api/cases/{case_id}/review",
        json={
            "action": "override",
            "reviewerId": "OPH-99",
            "overrideGrade": 4,
            "notes": "Confirmed",
        },
    )
    resp = client.post(f"/api/cases/{caseId}/report" if False else f"/api/cases/{case_id}/report")
    assert resp.status_code == 200
    body = resp.json()
    # AI grade is preserved
    assert body["report"]["aiPrediction"]["grade"] == 0
    # Final decision is the override
    assert body["report"]["finalDecision"]["grade"] == 4


# ─── 24. Effective status in list_cases ───────────────────────────────────

def test_list_cases_effective_status():
    # Create + screen + review
    case_id = _create_case()
    _upload_image(case_id)
    client.post(
        f"/api/cases/{case_id}/review",
        json={"action": "approve", "reviewerId": "OPH-10", "notes": ""},
    )
    resp = client.get("/api/cases")
    items = resp.json()
    entry = next(item for item in items if item["caseId"] == case_id)
    assert entry["status"] == "reviewed"


# ─── 25. Non-finite adapter output never crashes the endpoint ─────────────
# Regression: a real MATLAB engine can return NaN (e.g. confidence) for some
# images. Starlette's JSONResponse refuses to serialise NaN and returned a 500
# ("Out of range float values are not JSON compliant"), which the frontend
# surfaced as a generic "backend unreachable". NaN must become an honest null.

def test_screen_endpoint_handles_nan_adapter_output(monkeypatch):
    from app.services.matlab_adapter import BaseMatlabAdapter

    class NaNAdapter(BaseMatlabAdapter):
        def run_pipeline(self, image_path, metadata):
            return {
                "quality": {
                    "class": "good",
                    "score": float("nan"),
                    "failureReasons": [],
                    "recaptureReason": None,
                    "recaptureInstruction": None,
                },
                "grading": {
                    "rawProbs": [1.0, 0.0, 0.0, 0.0, float("nan")],
                    "grade": 1,
                    "referableProb": float("nan"),
                    "referable": False,
                },
                "calibrated": {
                    "calibratedProbs": [1.0, 0.0, 0.0, 0.0, float("nan")],
                    "confidence": float("nan"),
                    "uncertainty": float("nan"),
                    "reviewRequired": False,
                },
                "explain": None,
                "review": None,
            }

    monkeypatch.setattr(
        "app.services.matlab_adapter.default_adapter", lambda: NaNAdapter()
    )

    case_id = _create_case()
    resp = client.post(
        f"/api/cases/{case_id}/screen",
        files={"image": ("nan.jpg", b"\xff\xd8\xff\xd9", "image/jpeg")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["aiPrediction"]["confidence"] is None
    assert body["aiPrediction"]["uncertainty"] is None
    assert body["quality"]["score"] is None


def test_matlab_adapter_rejects_non_finite_numbers():
    from app.services.matlab_adapter import _scalar, _vector

    assert _scalar(float("nan")) is None
    assert _scalar(float("inf")) is None
    assert _scalar(float("-inf")) is None
    assert _scalar(0.58) == 0.58
    assert _scalar(None) is None
    assert _vector([0.5, float("nan")], 2) is None
    assert _vector([0.5, 0.5], 2) == [0.5, 0.5]


# ─── 27. Reviewer-name migration ─────────────────────────────────────────
# Legacy review rows stamped reviewer_id with the USERNAME ("doctor"); the
# migration rewrites them to the display name ("Dr. Meera Rao").

def test_backfill_reviewer_names_migrates_legacy_rows():
    from app.services import auth as auth_svc

    case_id = _create_case()
    # Simulate a legacy review recorded BEFORE the fix (username, not name).
    database_store.save_review(
        case_id,
        {
            "review": {
                "action": "approve",
                "reviewerId": "doctor",
                "status": "approved",
            },
            "finalDecision": {"grade": 0, "gradeLabel": "No DR", "referral": False},
            "aiGradeImmutable": True,
        },
    )

    updated = database_store.backfill_reviewer_names(auth_svc.username_to_name())
    assert updated >= 1
    review = database_store.load_review(case_id)
    assert review["review"]["reviewerId"] == "Dr. Meera Rao"
    # Idempotent: a second run changes nothing.
    assert database_store.backfill_reviewer_names(auth_svc.username_to_name()) == 0


# ─── 26. Explainability artifact content guards ──────────────────────────
# Regression: a degenerate (all-zero) Grad-CAM was blended into a flat navy
# wash and still served as available because the content check ran on the
# blended overlay instead of the raw heatmap.

def test_has_attention_content_rejects_degenerate_overlays():
    import numpy as np

    from app.services.artifacts import has_attention_content

    # All-zero honest fallback.
    assert not has_attention_content(np.zeros((100, 100, 3), dtype=np.uint8))
    # Uniform navy wash (jet(0) over a flat base) — a degenerate empty cam.
    assert not has_attention_content(np.full((100, 100, 3), 34, dtype=np.uint8))
    # Real overlay: varies across the fundus.
    real = np.zeros((100, 100, 3), dtype=np.uint8)
    real[:, :, 0] = np.arange(100, dtype=np.uint8).reshape(-1, 1) * 2
    assert has_attention_content(real)
    # Empty / None inputs.
    assert not has_attention_content(None)
    assert not has_attention_content(np.zeros((0, 0, 3), dtype=np.uint8))


def test_compute_explain_rejects_degenerate_cam():
    import numpy as np

    from app.services.explainability import _has_attention_content

    # All-zero Grad-CAM (model found nothing to attend to).
    assert not _has_attention_content(np.zeros((224, 224)))
    # Effectively empty (all values non-positive).
    assert not _has_attention_content(np.full((224, 224), -0.5))
    # A real map with a highlight is kept.
    cam = np.zeros((224, 224))
    cam[60:120, 90:140] = 0.9
    assert _has_attention_content(cam)
    assert not _has_attention_content(None)


# ─── 28. Artifact endpoint ───────────────────────────────────────────────
# Regression: ErrorCode.ARTIFACT_UNAVAILABLE was referenced but not defined,
# so resolve_artifact_path raised AttributeError -> unhandled -> 500. Missing
#/malformed/unknown artifacts must be honest 404s, never a server error.

def test_artifact_missing_file_returns_404():
    case_id = _create_case()
    resp = client.get(f"/api/cases/{case_id}/artifacts/gradcam")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "ARTIFACT_UNAVAILABLE"


def test_artifact_unknown_case_returns_404_not_500():
    # This is the P0 audit regression: was a 500 (AttributeError), never a 404.
    resp = client.get("/api/cases/RS-2026-99999/artifacts/gradcam")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "ARTIFACT_UNAVAILABLE"


def test_artifact_malformed_case_id_returns_404():
    resp = client.get("/api/cases/RS-2026-abc/artifacts/gradcam")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "ARTIFACT_UNAVAILABLE"


def test_artifact_unknown_name_returns_404():
    case_id = _create_case()
    resp = client.get(f"/api/cases/{case_id}/artifacts/gradfavicon")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "ARTIFACT_UNAVAILABLE"


def test_artifact_available_returns_png():
    import numpy as np

    from app.services import artifacts

    case_id = _create_case()
    # A real attention overlay (non-uniform, carries content) via the honest
    # artifact write path.
    attention = np.zeros((64, 64, 3), dtype=np.uint8)
    attention[20:40, 20:40] = (200, 120, 30)
    refs = artifacts.save_explain_artifacts(case_id, attention=attention, evidence=None)
    assert refs["gradcam"] is not None
    assert refs["evidence"] is None  # no evidence produced -> honest unavailable

    resp = client.get(f"/api/cases/{case_id}/artifacts/gradcam")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("image/png")
    assert resp.content


# ─── 29. PDF report download ─────────────────────────────────────────────
# Regression: the report-pdf endpoint must never 500 (reportlab present,
# missing data yields a structured 404) and must serve a real PDF download.

def test_report_pdf_after_screening():
    case_id = _create_case()
    _upload_image(case_id)

    resp = client.get(f"/api/cases/{case_id}/report/pdf")
    assert resp.status_code == 200, resp.text
    assert resp.headers["content-type"].startswith("application/pdf")
    assert resp.content.startswith(b"%PDF")
    assert len(resp.content) > 1000


def test_report_pdf_without_screening_returns_404():
    case_id = _create_case()
    resp = client.get(f"/api/cases/{case_id}/report/pdf")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "REPORT_UNAVAILABLE"


def test_report_pdf_unknown_case_returns_404():
    resp = client.get("/api/cases/RS-2026-99999/report/pdf")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "CASE_NOT_FOUND"
