# Simulink — District-Scale Telemedicine Capacity Model

SimEvents discrete-event model of the RetinaSense district telemedicine
workflow (docs/ARCHITECTURE.md §7). The model is real and runnable:
`DRTelemedicine.slx` is checked into this folder and is driven by the scenario /
capacity drivers below.

## Model

`DRTelemedicine.slx` — SimEvents entity-flow model (built with R2026a APIs by
`build_DRTelemedicine.m`):

```
[Patient Arrival Generator (exponential)] → [Acquisition Server (camera)]
  → [Recapture Quality Gate (10% retake loop)] → [Transmission Server (bandwidth)]
  → [AI FIFO Queue] → [AI Processing Server] → [Referral Router (8% referral)]
  → [Review Queue] → [Ophthalmologist Review Server × N]
  → [Completed Screening Sink] → 'completedPatients' log
```

All model parameters reference the base-workspace `params` struct provided by
`scenario_params.m`, so scenarios run without rebuilding the model.

## Data-source policy (AGENTS.md guardrail #1)

- **MEASURED** — `completedPatients` (count of entities entering the Completed
  sink), `throughput`, `annualCapacity`, `averageWaitingTime`,
  `queueLength`, `reviewerUtilization`. Throughput is only reported for a
  full simulated workday (8h); a partial window is never extrapolated.
  The waiting time / queue length come from the Acquisition Queue's
  `AverageWait` and `AverageQueueLength` SimEvents statistics, and
  `reviewerUtilization` from the Review Server's `Utilization` statistic —
  all enabled **post-build as passive listeners** by `instrument_for_kpis.m`
  (enabling them at build time would change entity structure and break the
  Input-Switch merges on R2026a, so the committed `DRTelemedicine.slx` is
  deliberately flow-only and instrumentation provably does not perturb
  throughput).
- **ANALYTICAL** — `meanWaitingTime`, `maxWaitingTime`, `acqUtilization`,
  `networkUtilization`, `aiUtilization`, `revUtilization`, `bottleneck`.
  These are M/M/1-style estimates computed from the same `scenario_params`
  used by the model, NOT SimEvents block-stat measurements.
- No fabricated results: if the model cannot run, drivers record
  `executionStatus = 'PENDING'` and return no numbers.

## Commands (run from this folder, on a MATLAB R2026a box with Simulink + SimEvents)

```matlab
smoke_DRTelemedicine()          % load → compile → 8h smoke run (full workday
                                % so every measured KPI observable is real);
                                % throws if a KPI is missing (nonzero exit in CI)
results = run_simulink_scenarios();   % 7 what-if scenarios, full workday each;
                                % prints MEASURED vs ANALYTICAL tables and
                                % persists simulink/output/*.json
analysis = analyze_capacity();  % bottleneck + 100k/yr feasibility verdict
```

`run_simulink_scenarios` writes the real results to
`simulink/output/district_capacity_results_<timestamp>.json` (runtime output,
git-ignored).

## Measured results (baseline, seed 42, 8h full workday)

The latest measured outcomes are recorded in `docs/AUDIT.md` (S-series findings)
and the JSON files under `simulink/output/`. Summary as of the audit sprint:

| Scenario | Completed (measured) | Measured annual | Analytical bottleneck |
|---|---|---|---|
| baseline (274/day arrival) | see `simulink/output/*.json` | see JSON | Acquisition |

The measured baseline (≈143 completed/day at the 274/day configured arrival
load, single camera at 3 min + 10% recapture) does **not** reach the 100,000/yr
(≈274/day) target. The capacity analysis therefore reports the target as
**not met** with the current single-acquisition-station configuration and
quantifies the required change (additional acquisition stations; see
`analyze_capacity.m`). Any capacity claim in the repo cites these measured
results, never an assumption.

## Build / rebuild

The checked-in model is **flow-only** (KPI observables are added at runtime by
`instrument_for_kpis.m`, never at build time). It can be rebuilt consciously:

```matlab
build_DRTelemedicine('DRTelemedicine', false)  % second arg = enable stats
```

`build_DRTelemedicine` loads and saves the model in **this folder** (path-robust)
and replaces the existing `.slx`, so only rebuild deliberately. The
`enableStats` argument exists for experiments; the committed model is always
built with `false`.