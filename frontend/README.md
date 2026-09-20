# RetinaSense Frontend

Web UI for the RetinaSense DR-screening prototype: upload a fundus image, run
the quality gate + AI grading, then complete the human-in-the-loop review that
produces the final decision and referral.

> **Guardrail**: the frontend never invents medical output. Every value you see
> comes from the backend (`backend/`), or is a clearly-labelled DEMO fixture
> behind a persistent banner when `VITE_DEMO_MODE=true`.

## Stack

- React 18 + TypeScript (strict) + Vite 5
- Custom dependency-free hash router (`#/…`)
- Plain CSS with a design-token system (no UI framework)
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
| `VITE_API_BASE_URL` | `http://localhost:8000` | Backend API root. |
| `VITE_DEMO_MODE` | unset | `true` → route everything through the DEMO client and show a persistent DEMO banner. |

Example: `VITE_DEMO_MODE=true npm run dev`

## Public site vs application

The `#/` route is a **public landing page** (own navbar/footer, no application
shell). Everything else renders inside the application shell.

| Route | Screen |
|---|---|
| `#/` | Public landing page (hero, stats, workflow, technology, features, human-in-the-loop, safety, CTA) |
| `#/login` | Standalone sign-in (seeded roles) |
| `#/dashboard` | Role-aware clinical console — operator (capture-only), doctor (AI briefs + review), district capacity |
| `#/screening` | New screening (metadata + image upload, runs the pipeline) |
| `#/cases/new` | Register a case, then continue to upload |
| `#/case/:id` | Full screening record (quality, AI result, review, final decision, report) |
| `#/case/:id/upload` | Attach the fundus image to an existing case and screen it |
| `#/result` | Latest result (most recent case) |
| `#/cases` | Case list with search + status filter |
| `#/review` | Review queue (screened, awaiting a human decision; ophthalmologist/admin only) |
| `#/reports` | Report listing |
| `#/reports/:id` | Report detail (printable) |

Non-DEMO routing requires an authenticated session; `/review` additionally
requires the `ophthalmologist` or `admin` role and redirects otherwise.

Landing-page section links (`#how-it-works`, `#technology`, `#features`,
`#safety`, …) are real anchors, not routes: the router resolves any hash that
does not start with `/` back to the landing page, which scrolls the matching
section.

## Design system

`src/index.css` is the single source of visual truth: CSS custom properties for
colour, type, spacing, radii, shadows and motion, plus one component layer
(`.btn*`, `.card*`, `.badge*`, `.alert*`, `.input/.select/.textarea`,
`.table*`, `.empty-state`, `.skeleton`, `.health-chip`, `.shell*`, `.l-*`).

- Palette: white + honeydew + soft mint + deep green/teal, light surfaces only.
- Status is never conveyed by colour alone — every badge carries text and an icon.
- Reusable primitives live in `src/components/ui/` (Button, Card, Badge, Alert,
  Field/Input/Select/Textarea/SearchInput, StatCard, PageHeader, EmptyState,
  Skeleton, Breadcrumbs, FileDropzone, Icon).
- `prefers-reduced-motion` disables non-essential animation.

## Backend API (integrated)

Endpoints called from `src/api/endpoints.ts`:

- `GET  /api/health` → `{status, matlabEngine, version, database?}`
- `POST /api/auth/login` → `{token, role, ...}`
- `GET  /api/auth/me` → current user info
- `POST /api/cases` → `{caseId, status}` (201)
- `POST /api/cases/{caseId}/screen` (multipart `image` + `patientId`/`eye`/`phcId`) → `CaseResponse`
- `GET  /api/cases/{caseId}` → `CaseResponse`
- `GET  /api/cases` → `CaseListItem[]`
- `GET  /api/cases/stats` → `CaseStats`
- `GET  /api/cases/{caseId}/image` → image blob
- `GET  /api/cases/{caseId}/artifacts/{name}` → explainability artifact blob
- `POST /api/cases/{caseId}/review` (JSON `{action, reviewerId, overrideGrade?, finalReferral?, notes?}`) → `ReviewResponse`
- `POST /api/cases/{caseId}/report` → `ReportResponse` (generate)
- `GET  /api/cases/{caseId}/report` → `ReportResponse`
- `GET  /api/cases/{caseId}/report/pdf` → PDF blob
- `GET  /api/simulation/capacity` → district capacity model results

Errors are normalised to `ApiError {kind, code, message}` and mapped to
friendly, honest UI messages (e.g. 503 `MATLAB_ENGINE_UNAVAILABLE` →
"Screening engine unavailable — no result was fabricated").

## Architecture / data flow

```
src/
  api/          types.ts (backend schema mirrors), client.ts (HTTP + errors),
                endpoints.ts (API or DEMO), demo.ts (clearly-labelled fixtures)
  auth/         session.ts (login state, role helpers like canReview)
  utils/        validation.ts (client image guard), format.ts, errors.ts
  hooks/        useCaseList.ts, useCaseBriefs.ts, useSimulationCapacity.ts,
                useStats.ts (API loading/error/reload)
  components/   AppShell, shared panels (Quality/AiPrediction/Explainability/
                FinalDecision/Review/Report/ImagePreview), ui/ primitives,
                landing/ sections, DashboardStats/DashboardCases
  pages/        LandingPage, LoginPage, DashboardPage + role dashboards (in
                pages/dashboards/: Operator/Doctor/Simulation/ScreeningConsole),
                NewScreeningPage, CreateCasePage, CaseUploadPage, CasesPage,
                CaseViewPage, LatestResultPage, ReviewQueuePage, ReportsPage,
                ReportDetailPage, NotFoundPage
  router.ts     hash router (+ dynamic path parsers)
```

Flow: `NewScreeningPage` validates the file client-side (JPEG/PNG, ≤20 MB —
the same limits the backend enforces authoritatively), calls `createCase` →
`screenCase`, then routes to `#/case/<id>`. `CaseViewPage` shows the quality
gate result, the **immutable AI prediction**, explainability (real backend
artifacts only — nothing is drawn or invented), the human review, and the
final decision. An ungradable image shows recapture instructions and **no**
grade, report, or review — nothing is fabricated.

The dashboard dispatches to a role-specific view: **Operator** sees a
capture-only console, **Doctor** sees AI briefs and review work, **Simulation**
shows the measured district-capacity model results (real backend numbers, or
an honest empty state when the endpoint is unavailable — never fabricated).

### Landing hero

The hero uses `frontend/public/hero-section.mp4`, referenced as
`/hero-section.mp4`. If that file is missing or cannot be played, the hero
falls back to a designed static panel — no replacement footage or fake
screenshot is generated.

### Demo mode

`VITE_DEMO_MODE=true` swaps the API layer for `demo.ts` fixtures (good /
borderline / ungradable / review-required scenarios, selectable on the
dashboard). All demo output carries the persistent "DEMO MODE — SIMULATED
DATA" banner and is never presented as a real screening.
