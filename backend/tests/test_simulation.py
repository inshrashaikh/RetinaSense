"""Tests for the Simulink district-capacity endpoint.

The endpoint serves the persisted scenario results written by
simulink/run_simulink_scenarios.m. It must report real data when result files
exist and an honest `available: false` when they do not — never a fabricated
figure.
"""
from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient

import app.config as cfg
from app.main import app


client = TestClient(app, raise_server_exceptions=False)


def _login(role: str) -> str:
    creds = {
        "admin": ("admin", "admin123"),
        "doctor": ("doctor", "doctor123"),
        "operator": ("operator", "operator123"),
    }[role]
    resp = client.post("/api/auth/login", json={"username": creds[0], "password": creds[1]})
    assert resp.status_code == 200, resp.text
    return resp.json()["token"]


def _sample_payload() -> dict:
    return {
        "generatedAt": "2026-09-17 18:04:41",
        "matlabVersion": "9.17.0 (R2026a)",
        "simulinkVersion": "23.2 (R2026a)",
        "simEventsVersion": "23.2 (R2026a)",
        "modelFile": "DRTelemedicine.slx",
        "dataSourcePolicy": "MEASURED: ...",
        "results": [
            {
                "scenario": "baseline",
                "executionStatus": "SUCCESS",
                "measurementWindow": "FULL_WORKDAY",
                "patientsPerDay": 274,
                "bandwidthMbps": 2.0,
                "numReviewers": 2,
                "simTimeHours": 8,
                "completedPatients": 143,
                "throughput": 143.0,
                "annualCapacity": 52195,
                "averageWaitingTime": 5225.2,
                "meanWaitingTime": 1845.7,
                "maxWaitingTime": 5537.1,
                "queueLength": 36.8,
                "acqUtilization": 0.976,
                "networkUtilization": 0.21,
                "aiUtilization": 0.35,
                "revUtilization": 0.054,
                "reviewerUtilization": 0.054,
                "bottleneck": "Acquisition",
            },
            {
                "scenario": "solo_reviewer",
                "executionStatus": "PENDING",
                "measurementWindow": "",
                "patientsPerDay": 274,
                "bandwidthMbps": 2.0,
                "numReviewers": 1,
                "simTimeHours": 8,
                "completedPatients": [],
                "throughput": [],
                "annualCapacity": [],
                "averageWaitingTime": [],
                "meanWaitingTime": [],
                "maxWaitingTime": [],
                "queueLength": [],
                "acqUtilization": [],
                "networkUtilization": [],
                "aiUtilization": [],
                "revUtilization": [],
                "reviewerUtilization": [],
                "bottleneck": "PENDING",
            },
        ],
    }


@pytest.fixture()
def _sim_output_dir(tmp_path, monkeypatch):
    """Point the simulation output dir at a temp folder for the test."""
    out_dir = tmp_path / "simulink-output"
    out_dir.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(cfg, "SIMULATION_OUTPUT_DIR", out_dir)
    return out_dir


def test_capacity_requires_admin():
    token = _login("doctor")
    headers = {"Authorization": f"Bearer {token}"}
    resp = client.get("/api/simulation/capacity", headers=headers)
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "FORBIDDEN"


def test_capacity_reports_absent(_sim_output_dir):
    headers = {"Authorization": f"Bearer {_login('admin')}"}
    resp = client.get("/api/simulation/capacity", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["available"] is False
    assert body["latest"] is None
    assert body["runs"] == []
    # Reference target is always reported, clearly separated from measured.
    assert body["target"]["annualPatients"] == 100_000
    assert "SIH 2026" in body["target"]["note"]


def test_capacity_serves_latest_run(_sim_output_dir):
    (cfg.SIMULATION_OUTPUT_DIR / "district_capacity_results_20260917_180441.json").write_text(
        json.dumps(_sample_payload()), encoding="utf-8"
    )
    headers = {"Authorization": f"Bearer {_login('admin')}"}
    resp = client.get("/api/simulation/capacity", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["available"] is True
    assert body["latest"]["generatedAt"] == "2026-09-17 18:04:41"
    assert body["runs"][0]["file"] == "district_capacity_results_20260917_180441.json"

    results = body["latest"]["results"]
    assert len(results) == 2
    baseline = results[0]
    assert baseline["scenario"] == "baseline"
    assert baseline["throughput"] == 143.0
    assert baseline["annualCapacity"] == 52195
    assert baseline["bottleneck"] == "Acquisition"

    # MATLAB encodes NaN as [] — that must come back as null, never a number.
    pending = results[1]
    assert pending["executionStatus"] == "PENDING"
    assert pending["throughput"] is None
    assert pending["annualCapacity"] is None


def test_capacity_uses_newest_run(_sim_output_dir):
    older = dict(_sample_payload())
    older["generatedAt"] = "2026-09-16 10:00:00"
    older["results"][0]["throughput"] = 120.0
    newer = dict(_sample_payload())
    newer["generatedAt"] = "2026-09-17 18:04:41"

    (cfg.SIMULATION_OUTPUT_DIR / "district_capacity_results_20260916_100000.json").write_text(
        json.dumps(older), encoding="utf-8"
    )
    (cfg.SIMULATION_OUTPUT_DIR / "district_capacity_results_20260917_180441.json").write_text(
        json.dumps(newer), encoding="utf-8"
    )
    headers = {"Authorization": f"Bearer {_login('admin')}"}
    resp = client.get("/api/simulation/capacity", headers=headers)
    body = resp.json()
    assert len(body["runs"]) == 2
    assert body["latest"]["results"][0]["throughput"] == 143.0
    assert body["latest"]["generatedAt"] == "2026-09-17 18:04:41"


def test_capacity_ignores_corrupt_json(_sim_output_dir):
    (cfg.SIMULATION_OUTPUT_DIR / "district_capacity_results_20260917_000000.json").write_text(
        "{not json", encoding="utf-8"
    )
    headers = {"Authorization": f"Bearer {_login('admin')}"}
    resp = client.get("/api/simulation/capacity", headers=headers)
    body = resp.json()
    assert body["available"] is False