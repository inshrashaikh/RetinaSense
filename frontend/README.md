# RetinaSense Frontend

Web UI for the RetinaSense DR-screening prototype: upload a fundus image, run
the quality gate + AI grading, then complete the human-in-the-loop review that
produces the final decision and referral.

> **Guardrail**: the frontend never invents medical output. Every value you see
> comes from the backend (`backend/`), or is a clearly-labelled DEMO fixture
> behind a persistent banner when `VITE_DEMO_MODE=true`.

## Stack

- React 18 + TypeScript (strict) + Vite 5
- Custom dependency-free hash router (`#/`, `#/case/<id>`)
- Plain CSS (no UI framework)
- Vitest + Testing Library + jsdom for tests

## Setup & run

```bash
npm install
npm run dev            # http://localhost:5173
```

Build and preview:

```bash
npm run build          # tsc --noEmit && vite build
npm run preview        # http://localhost:4173
```

Tests and typecheck:

```bash
npm test               # vitest run (CI-style)
npm run test:watch
npm run typecheck      # tsc --noEmit
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `VITE_API_BASE_URL` | `http://127.0.0.1:8000` | Backend API root. |
| `VITE_DEMO_MODE` | unset | `true` → route everything through the DEMO client and show a persistent DEMO banner. |

Example: `VITE_DEMO_MODE=true npm run dev`

## Backend API (integrated)

From `backend/app/routes` + `backend/app/models/schemas.py`:

- `GET /api/health` → `{status, matlabEngine, version}`
- `POST /api/cases` → `{caseId, status}` (201)
- `POST /api/cases/{caseId}/screen` (multipart `image` + `patientId`/`eye`/`phcId`) → `CaseResponse`
- `GET /api/cases/{caseId}` → `CaseResponse`
- `POST /api/cases/{caseId}/review` (JSON `{action, reviewerId, overrideGrade?, finalReferral?, notes?}`) → `ReviewResponse`
- `GET /api/cases/{caseId}/report` → `ReportResponse` (404 `REPORT_UNAVAILABLE` until generated)

Errors are normalised to `ApiError {kind, code, message}` and mapped to
friendly, honest UI messages (e.g. 503 `MATLAB_ENGINE_UNAVAILABLE` →
"Screening engine unavailable — no result was fabricated").

## Architecture / data flow

```
src/
  api/          types.ts (backend schema mirrors), client.ts (HTTP + errors),
                endpoints.ts (API or DEMO), demo.ts (clearly-labelled fixtures)
  utils/        validation.ts (client image guard), format.ts, errors.ts
  components/   QualityPanel, AiPredictionPanel, ExplainabilityPanel,
                FinalDecisionPanel, ReviewPanel, ReportSection, banners…
  pages/        DashboardPage, NewScreeningPage, CaseViewPage
  storage.ts    recent cases (localStorage) + in-session image preview (memory)
  router.ts     hash router
```

Flow: `NewScreeningPage` validates the file client-side (JPEG/PNG, ≤20 MB —
same limits the backend enforces authoritatively), calls `createCase` →
`screenCase`, then routes to `#/case/<id>`. `CaseViewPage` shows the quality
gate result, the **immutable AI prediction**, explainability (real backend
artifacts only — nothing is drawn or invented), the human review, and the
final decision. An ungradable image shows recapture instructions and **no**
grade, report, or review — nothing is fabricated.

### Demo mode

`VITE_DEMO_MODE=true` swaps the API layer for `demo.ts` fixtures (good /
borderline / ungradable / review-required scenarios, selectable on the
dashboard). All demo output carries the persistent "DEMO MODE — SIMULATED
DATA" banner and is never presented as a real screening.

### Notes on this prototype

- The backend stores images on disk but exposes no image/list endpoints, so
  the frontend keeps the uploaded preview in memory for the session. After a
  reload the preview is honestly labelled "Image unavailable for this session".
- Recent case ids live in localStorage (best-effort; the backend has no case-list endpoint).