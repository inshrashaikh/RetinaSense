/**
 * Role-based dashboards — the signed-in role decides which dashboard renders,
 * which destinations the sidebar exposes, and what each dashboard is allowed
 * to show. Every figure comes from the mocked backend; nothing is invented.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';

const api = vi.hoisted(() => ({
  login: vi.fn(),
  createCase: vi.fn(),
  screenCase: vi.fn(),
  getCase: vi.fn(),
  listCases: vi.fn(),
  fetchCaseImage: vi.fn(async () => new Blob()),
  submitReview: vi.fn(),
  fetchHealth: vi.fn(),
  fetchCaseStats: vi.fn(),
  generateReport: vi.fn(),
  fetchSimulationCapacity: vi.fn(),
}));

vi.mock('../src/api/endpoints', () => ({
  isDemoMode: false,
  login: api.login,
  createCase: api.createCase,
  screenCase: api.screenCase,
  getCase: api.getCase,
  listCases: api.listCases,
  fetchCaseImage: api.fetchCaseImage,
  submitReview: api.submitReview,
  fetchHealth: api.fetchHealth,
  fetchCaseStats: api.fetchCaseStats,
  generateReport: api.generateReport,
  fetchSimulationCapacity: api.fetchSimulationCapacity,
}));

import App from '../src/App';
import { DashboardPage } from '../src/pages/DashboardPage';
import { saveSession } from '../src/auth/session';

const STATS = {
  totalCases: 7,
  screeningsCompleted: 5,
  pendingReviews: 2,
  recaptureRequired: 1,
  reviewed: 3,
  created: 1,
};

const CASE_ITEMS = [
  { caseId: 'RS-2026-00001', status: 'created', patientId: 'P-1', eye: 'OD', phcId: 'PHC-1', createdAt: '2026-09-11T10:00:00Z' },
  { caseId: 'RS-2026-00002', status: 'completed', patientId: 'P-2', eye: 'OS', phcId: 'PHC-1', createdAt: '2026-09-12T10:00:00Z' },
  { caseId: 'RS-2026-00003', status: 'recapture_required', patientId: 'P-3', eye: 'OD', phcId: 'PHC-1', createdAt: '2026-09-13T10:00:00Z' },
  { caseId: 'RS-2026-00004', status: 'reviewed', patientId: 'P-4', eye: 'OS', phcId: 'PHC-1', createdAt: '2026-09-14T10:00:00Z' },
];

const COMPLETED_CASE = {
  caseId: 'RS-2026-00002',
  status: 'completed',
  quality: { class: 'good', score: 0.9, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
  aiPrediction: {
    grade: 1,
    gradeLabel: 'Mild NPDR',
    probabilities: null,
    referable: false,
    confidence: 0.7,
    uncertainty: 0.2,
    reviewRequired: false,
  },
  explainability: { gradCamAvailable: true, gradCamPath: '/generated/gradcam.png', evidenceAvailable: false, evidencePath: null },
  humanReview: null,
  finalDecision: null,
};

/**
 * A sample of the real GET /api/simulation/capacity shape (mirrors
 * simulate the persisted MEASURED results JSON contract).
 */
const SIM_CAPACITY = {
  available: true,
  latest: {
    generatedAt: '2026-09-17 18:04:41',
    matlabVersion: 'R2026a',
    simulinkVersion: 'R2026a',
    simEventsVersion: 'R2026a',
    modelFile: 'DRTelemedicine.slx',
    dataSourcePolicy: 'MEASURED: real SimEvents block statistics',
    results: [
      {
        scenario: 'baseline',
        executionStatus: 'SUCCESS',
        measurementWindow: 'FULL_WORKDAY',
        patientsPerDay: 274,
        bandwidthMbps: 2.0,
        numReviewers: 2,
        simTimeHours: 8,
        completedPatients: 143,
        throughput: 143.0,
        annualCapacity: 52195,
        averageWaitingTime: 5225.2,
        meanWaitingTime: 1845.7,
        maxWaitingTime: 5537.1,
        queueLength: 36.8,
        acqUtilization: 0.976,
        networkUtilization: 0.21,
        aiUtilization: 0.35,
        revUtilization: 0.054,
        reviewerUtilization: 0.054,
        bottleneck: 'Acquisition',
      },
      {
        scenario: 'solo_reviewer',
        executionStatus: 'PENDING',
        measurementWindow: '',
        patientsPerDay: 274,
        bandwidthMbps: 2.0,
        numReviewers: 1,
        simTimeHours: 8,
        completedPatients: null,
        throughput: null,
        annualCapacity: null,
        averageWaitingTime: null,
        meanWaitingTime: null,
        maxWaitingTime: null,
        queueLength: null,
        acqUtilization: null,
        networkUtilization: null,
        aiUtilization: null,
        revUtilization: null,
        reviewerUtilization: null,
        bottleneck: 'PENDING',
      },
    ],
  },
  runs: [],
  target: {
    annualPatients: 100_000,
    dailyEquivalent: 274,
    note: 'Reference target from the SIH 2026 problem statement.',
  },
};

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.location.hash = '';

  api.fetchHealth.mockResolvedValue({ status: 'ok', matlabEngine: true, version: '0.1.0', database: 'ok' });
  api.fetchCaseStats.mockResolvedValue(STATS);
  api.listCases.mockResolvedValue(CASE_ITEMS);
  api.getCase.mockResolvedValue(COMPLETED_CASE);
  api.fetchSimulationCapacity.mockResolvedValue(SIM_CAPACITY);
});

describe('dashboard role dispatch', () => {
  it('falls back to the generic console when no role is known', async () => {
    render(<DashboardPage demoMode={false} />);
    expect(screen.getByRole('heading', { name: 'RetinaSense screening console' })).toBeInTheDocument();
    await screen.findByText('Screenings completed');
  });

  it('renders the PHC operator operations dashboard without review controls', async () => {
    saveSession('token', { id: 2, username: 'operator', name: 'PHC Operator', role: 'phc_operator' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByRole('heading', { name: 'Screening operations' })).toBeInTheDocument();
    // The label appears on both the stat card and the worklist header.
    expect(screen.getAllByText('Awaiting screening').length).toBeGreaterThan(0);
    expect(screen.getByText('Awaiting ophthalmologist')).toBeInTheDocument();
    expect(screen.getByText(/Final decisions are made by an ophthalmologist/i)).toBeInTheDocument();

    // Operators never get the clinical review destination.
    expect(screen.queryByRole('link', { name: 'Review queue' })).not.toBeInTheDocument();
  });

  it('renders the ophthalmologist clinical review dashboard with AI briefs', async () => {
    saveSession('token', { id: 1, username: 'doctor', name: 'Dr. Meera Rao', role: 'ophthalmologist' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByRole('heading', { name: 'Clinical review' })).toBeInTheDocument();
    expect(screen.getByText('Pending clinical review')).toBeInTheDocument();
    expect(screen.getByText('Reviews recorded')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Review queue' })).toBeInTheDocument();

    // The per-case AI brief is fetched and shown for the pending case.
    expect(await screen.findByText('Mild NPDR')).toBeInTheDocument();
    expect(screen.getByText('Not referable')).toBeInTheDocument();
    expect(screen.getByText('Grad-CAM')).toBeInTheDocument();
  });

  it('renders the district operations dashboard with measured capacity', async () => {
    saveSession('token', { id: 3, username: 'admin', name: 'District Admin', role: 'admin' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByRole('heading', { name: 'Capacity & district operations' })).toBeInTheDocument();
    expect(screen.getByText('District telemedicine workflow')).toBeInTheDocument();
    expect(screen.getByText('Measured baseline capacity')).toBeInTheDocument();
    expect(screen.getByText('Scenario comparison')).toBeInTheDocument();

    // Measured baseline figures are shown (from the mocked simulation result).
    expect(screen.getAllByText('143/day').length).toBeGreaterThan(0);
    expect(screen.getAllByText('52,195').length).toBeGreaterThan(0);
    expect(screen.getAllByText('Acquisition').length).toBeGreaterThan(0);

    // The 100k target is separated and never presented as measured.
    expect(screen.getByText(/100,000 patients\/year is a reference target/i)).toBeInTheDocument();

    // PENDING scenarios are never rendered as numbers.
    expect(screen.queryByText('solo_reviewer')).toBeNull();
  });

  it('reports honestly when no measured simulation results exist', async () => {
    api.fetchSimulationCapacity.mockResolvedValue({
      available: false,
      latest: null,
      runs: [],
      target: { annualPatients: 100_000, dailyEquivalent: 274, note: 'Ref' },
    });
    saveSession('token', { id: 3, username: 'admin', name: 'District Admin', role: 'admin' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByText(/No measured simulation results yet/i)).toBeInTheDocument();
    // No fabricated figure is rendered.
    expect(screen.queryByText('143/day')).not.toBeInTheDocument();
  });
});

describe('role-based access', () => {
  it('lets an administrator open the review queue', async () => {
    saveSession('token', { id: 3, username: 'admin', name: 'Admin User', role: 'admin' });
    window.location.hash = '#/review';
    render(<App />);

    expect(await screen.findByRole('heading', { name: 'Review queue' })).toBeInTheDocument();
  });

  it('shows the account role label in the topbar', async () => {
    saveSession('token', { id: 1, username: 'doctor', name: 'Dr. Meera Rao', role: 'ophthalmologist' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByText('Ophthalmologist')).toBeInTheDocument();
  });
});

describe('doctor AI brief honesty', () => {
  it('reports a brief it could not read instead of guessing', async () => {
    saveSession('token', { id: 1, username: 'doctor', name: 'Dr. Meera Rao', role: 'ophthalmologist' });
    window.location.hash = '#/dashboard';
    api.getCase.mockRejectedValue({ kind: 'network', code: 'NETWORK_ERROR', message: 'down' });

    render(<App />);

    expect(await screen.findByText('AI brief unavailable')).toBeInTheDocument();
    expect(screen.queryByText('Mild NPDR')).not.toBeInTheDocument();
  });
});

describe('dashboard UI robustness', () => {
  it('keeps a long opaque case id visible without breaking the layout', async () => {
    const longId = 'RS-2026-0000123456789012345678901234567890';
    api.listCases.mockResolvedValue([
      { ...CASE_ITEMS[0], caseId: longId, patientId: 'PATIENT-TOKEN-012345678901234567890' },
    ]);
    saveSession('token', { id: 2, username: 'operator', name: 'PHC Operator', role: 'phc_operator' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByText(longId)).toBeInTheDocument();
    const recentCard = screen.getByRole('region', { name: 'Recent cases' });
    expect(within(recentCard).getByText(longId)).toBeInTheDocument();
  });
});
