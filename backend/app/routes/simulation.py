"""Simulink district-capacity endpoints (admin-only, read-only).

Serves the persisted scenario results written by
simulink/run_simulink_scenarios.m (simulink/output/*.json, git-ignored). The
JSON is the runtime artifact of a real SimEvents simulation: no number is
fabricated here, and when no results exist the endpoint reports `available:
false` rather than assuming a value.
"""
from __future__ import annotations

import json
from pathlib import Path

from fastapi import APIRouter, Depends

import app.config as cfg
from ..auth_deps import require_roles
from ..models.schemas import (
    CapacityTarget,
    ScenarioResult,
    SimulationCapacityResponse,
    SimulationRunInfo,
    SimulationRunPayload,
)

router = APIRouter()


def _clean(value):
    """MATLAB jsonencode emits NaN/Inf as [] — turn empty lists back to None."""
    if isinstance(value, list) and len(value) == 0:
        return None
    return value


def _parse_run(filepath: Path) -> SimulationRunPayload | None:
    try:
        with filepath.open(encoding="utf-8") as fh:
            raw = json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None

    results_raw = raw.get("results")
    results: list[ScenarioResult] = []
    if isinstance(results_raw, list):
        for item in results_raw:
            if isinstance(item, dict):
                results.append(
                    ScenarioResult(**{k: _clean(v) for k, v in item.items()})
                )

    return SimulationRunPayload(
        generatedAt=_clean(raw.get("generatedAt")),
        matlabVersion=_clean(raw.get("matlabVersion")),
        simulinkVersion=_clean(raw.get("simulinkVersion")),
        simEventsVersion=_clean(raw.get("simEventsVersion")),
        modelFile=_clean(raw.get("modelFile")),
        dataSourcePolicy=_clean(raw.get("dataSourcePolicy")),
        results=results,
    )


@router.get(
    "/api/simulation/capacity",
    response_model=SimulationCapacityResponse,
    dependencies=[Depends(require_roles("admin"))],
)
def simulation_capacity() -> SimulationCapacityResponse:
    target = CapacityTarget(
        annualPatients=cfg.SIM_TARGET_ANNUAL_PATIENTS,
        dailyEquivalent=round(
            cfg.SIM_TARGET_ANNUAL_PATIENTS / cfg.SIM_WORKDAYS_PER_YEAR, 1
        ),
        note=(
            "100,000 patients/year is the SIH 2026 scalability target — a "
            "reference figure. Measured throughput is reported separately and "
            "never equals this target automatically."
        ),
    )

    out_dir = cfg.SIMULATION_OUTPUT_DIR
    if not out_dir.is_dir():
        return SimulationCapacityResponse(available=False, target=target)

    files = sorted(
        out_dir.glob("district_capacity_results_*.json"),
        reverse=True,
    )
    if not files:
        return SimulationCapacityResponse(available=False, target=target)

    runs: list[SimulationRunInfo] = []
    latest_payload: SimulationRunPayload | None = None
    for path in files:
        payload = _parse_run(path)
        if payload is None:
            continue
        run = SimulationRunInfo(
            file=path.name,
            generatedAt=payload.generatedAt,
            results=payload.results,
        )
        runs.append(run)
        if latest_payload is None:
            latest_payload = payload

    return SimulationCapacityResponse(
        available=latest_payload is not None,
        latest=latest_payload,
        runs=runs,
        target=target,
    )