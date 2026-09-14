/**
 * Cases / Review queue / Reports / Report detail pages — all sourced from the
 * backend API, never from localStorage.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

const api = vi.hoisted(() => ({
  createCase: vi.fn(),
  screenCase: vi.fn(),
  getCase: vi.fn(),
  listCases: vi.fn(),
  fetchCaseImage: vi.fn(async () => new Blob()),
  fetchCaseArtifact: vi.fn(async () => new Blob()),
  submitReview: vi.fn(),
  fetchReport: vi.fn(),
  fetchHealth: vi.fn(),
  fetchCaseStats: vi.fn(),
  generateReport: vi.fn(),
}));

vi.mock('../src/api/endpoints', () => ({
  isDemoMode: false,
  createCase: api.createCase,
  screenCase: api.screenCase,
  getCase: api.getCase,
  listCases: api.listCases,
  fetchCaseImage: api.fetchCaseImage,
  fetchCaseArtifact: api.fetchCaseArtifact,
  submitReview: api.submitReview,
  fetchReport: api.fetchReport,
  fetchHealth: api.fetchHealth,
  fetchCaseStats: api.fetchCaseStats,
  generateReport: api.generateReport,
}));

import { CasesPage } from '../src/pages/CasesPage';
import { ReviewQueuePage } from '../src/pages/ReviewQueuePage';
import { ReportsPage } from '../src/pages/ReportsPage';
import { ReportDetailPage } from '../src/pages/ReportDetailPage';
import { LatestResultPage } from '../src/pages/LatestResultPage';

const allCases = [
  { caseId: 'RS-2026-00002', status: 'completed', patientId: 'P-2', eye: 'OD', phcId: 'PHC-1', createdAt: '2026-09-10T10:00:00Z' },
  { caseId: 'RS-2026-00001', status: 'reviewed', patientId: 'P-1', eye: 'OS', phcId: 'PHC-1', createdAt: '2026-09-09T10:00:00Z' },
];

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';
  api.listCases.mockResolvedValue([...allCases]);
});

describe('CasesPage', () => {
  it('renders all cases with statuses from the backend', async () => {
    render(<CasesPage />);
    expect(await screen.findByText('RS-2026-00002')).toBeInTheDocument();
    expect(screen.getByText('RS-2026-00001')).toBeInTheDocument();
    expect(screen.getByText('Screened — pending review')).toBeInTheDocument();
    expect(screen.getByText('Reviewed')).toBeInTheDocument();
  });

  it('shows an empty state when there are no cases', async () => {
    api.listCases.mockResolvedValue([]);
    render(<CasesPage />);
    expect(await screen.findByText(/No screenings have been run/i)).toBeInTheDocument();
  });
});

describe('ReviewQueuePage', () => {
  it('shows only the cases waiting for a human decision', async () => {
    render(<ReviewQueuePage />);
    expect(await screen.findByText('RS-2026-00002')).toBeInTheDocument();
    expect(screen.queryByText('RS-2026-00001')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Review' })).toBeInTheDocument();
  });

  it('shows a friendly empty state when nothing is pending', async () => {
    api.listCases.mockResolvedValue([allCases[1]]);
    render(<ReviewQueuePage />);
    expect(await screen.findByText('Nothing to review')).toBeInTheDocument();
  });
});

describe('ReportsPage', () => {
  it('lists screened cases with report links', async () => {
    render(<ReportsPage />);
    expect(await screen.findByText('RS-2026-00002')).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'View report' })).toHaveLength(2);
  });
});

describe('ReportDetailPage', () => {
  it('loads the case and generates a report from the backend', async () => {
    api.getCase.mockResolvedValue({
      caseId: 'RS-2026-00002',
      status: 'completed',
      quality: { class: 'good', score: 0.92, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
      aiPrediction: { grade: 2, gradeLabel: 'Moderate NPDR', referable: true, confidence: 0.81, uncertainty: 0.11, reviewRequired: false },
      explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
      humanReview: null,
      finalDecision: null,
    });
    api.generateReport.mockResolvedValue({
      caseId: 'RS-2026-00002',
      summary: 'Case RS-2026-00002 (eye OD). Quality: Good (score 92%). AI grade: 2 (Moderate NPDR), referable: yes. No human review recorded yet.',
      disclaimer: 'Screening decision-support only. Not a diagnosis and not a replacement for an ophthalmologist.',
      report: {
        caseId: 'RS-2026-00002',
        status: 'completed',
        patientId: 'P-2',
        eye: 'OD',
        phcId: 'PHC-1',
        quality: { class: 'good', score: 0.92, failureReasons: [] },
        aiPrediction: { grade: 2, gradeLabel: 'Moderate NPDR', referable: true, confidence: 0.81, uncertainty: 0.11, reviewRequired: false },
        explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
        humanReview: null,
        finalDecision: null,
        disclaimer: 'Screening decision-support only.',
        summary: 'Case summary.',
      },
    });

    render(<ReportDetailPage caseId="RS-2026-00002" />);

    expect(await screen.findByText(/Screening report/)).toBeInTheDocument();
    expect(screen.getByText('2 · Moderate NPDR')).toBeInTheDocument();
    expect(screen.getByText(/No human review recorded yet/i)).toBeInTheDocument();
    expect(api.generateReport).toHaveBeenCalledWith('RS-2026-00002');
  });

  it('does not fabricate a report when the backend has none', async () => {
    api.getCase.mockResolvedValue({
      caseId: 'RS-2026-00002',
      status: 'completed',
      quality: { class: 'good', score: 0.92, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
      aiPrediction: null,
      explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
      humanReview: null,
      finalDecision: null,
    });
    api.generateReport.mockRejectedValue({
      kind: 'http', code: 'REPORT_UNAVAILABLE', message: 'No report yet.', httpStatus: 404,
    });

    render(<ReportDetailPage caseId="RS-2026-00002" />);

    expect(await screen.findByText('Report not available')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Retry report generation' })).toBeInTheDocument();
  });
});

describe('LatestResultPage', () => {
  it('opens the most recent case as the screening result', async () => {
    api.listCases.mockResolvedValue([allCases[0]]);
    api.getCase.mockResolvedValue({
      caseId: 'RS-2026-00002',
      status: 'completed',
      quality: { class: 'good', score: 0.92, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
      aiPrediction: { grade: 2, gradeLabel: 'Moderate NPDR', referable: true, confidence: 0.81, uncertainty: 0.11, reviewRequired: false },
      explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
      humanReview: null,
      finalDecision: null,
    });

    render(<LatestResultPage />);

    expect(await screen.findByText('Case RS-2026-00002')).toBeInTheDocument();
    expect(screen.getByText('2 · Moderate NPDR')).toBeInTheDocument();
  });

  it('shows an honest empty state when no screening exists', async () => {
    api.listCases.mockResolvedValue([]);
    const user = userEvent.setup();

    render(<LatestResultPage />);
    expect(await screen.findByText('No result yet')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Start a new screening' }));
    expect(window.location.hash).toBe('#/screening');
  });
});