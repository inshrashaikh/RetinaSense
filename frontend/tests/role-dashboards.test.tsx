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

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.location.hash = '';

  api.fetchHealth.mockResolvedValue({ status: 'ok', matlabEngine: true, version: '0.1.0', database: 'ok' });
  api.fetchCaseStats.mockResolvedValue(STATS);
  api.listCases.mockResolvedValue(CASE_ITEMS);
  api.getCase.mockResolvedValue(COMPLETED_CASE);
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

  it('renders the administrator monitoring dashboard with honest gaps', async () => {
    saveSession('token', { id: 3, username: 'admin', name: 'Admin User', role: 'admin' });
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(await screen.findByRole('heading', { name: 'System administration' })).toBeInTheDocument();
    expect(screen.getByText('System health')).toBeInTheDocument();
    expect(screen.getByText('Case-store overview')).toBeInTheDocument();
    expect(screen.getByText('Operational backlog')).toBeInTheDocument();
    // Missing backend capabilities are stated, not faked.
    expect(screen.getByText(/does not provide user\/role management/i)).toBeInTheDocument();
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
