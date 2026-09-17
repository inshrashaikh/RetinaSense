/**
 * Dashboard — stats cards, health chip, recent-cases table, and the
 * AI-assisted + human-in-the-loop callout. All numbers come from the backend.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';

const api = vi.hoisted(() => ({
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

import { DashboardPage } from '../src/pages/DashboardPage';

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';

  api.fetchHealth.mockResolvedValue({ status: 'ok', matlabEngine: false, version: '0.1.0', database: 'ok' });
  api.fetchCaseStats.mockResolvedValue({
    totalCases: 5,
    screeningsCompleted: 3,
    pendingReviews: 2,
    recaptureRequired: 1,
    reviewed: 1,
    created: 1,
  });
  api.listCases.mockResolvedValue([
    { caseId: 'RS-2026-00005', status: 'completed', patientId: 'P-5', eye: 'OD', phcId: 'PHC-1', createdAt: '2026-09-10T10:00:00Z' },
    { caseId: 'RS-2026-00004', status: 'reviewed', patientId: 'P-4', eye: 'OS', phcId: 'PHC-1', createdAt: '2026-09-09T10:00:00Z' },
  ]);
});

describe('DashboardPage', () => {
  it('shows RetinaSense branding/title, New screening CTA and then renders backend stats', async () => {
    render(<DashboardPage demoMode={false} />);

    expect(screen.getByText('RetinaSense screening console')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'New screening' })).toBeInTheDocument();

    expect(await screen.findAllByText('5')).not.toHaveLength(0);
    expect(screen.getByText('Screenings completed')).toBeInTheDocument();
    expect(screen.getByText('Pending reviews')).toBeInTheDocument();
  });

  it('is honest when the backend is unreachable', async () => {
    api.fetchCaseStats.mockRejectedValue({ kind: 'network', code: 'NETWORK_ERROR', message: 'down' });
    api.fetchHealth.mockRejectedValue({ kind: 'network', code: 'NETWORK_ERROR', message: 'down' });

    render(<DashboardPage demoMode={false} />);

    expect(await screen.findByText(/Statistics are unavailable while the backend is unreachable/i)).toBeInTheDocument();
    expect((await screen.findAllByText('Backend unreachable — real screening unavailable')).length).toBeGreaterThan(0);
  });

  it('lists recent cases from the backend with their status', async () => {
    render(<DashboardPage demoMode={false} />);

    expect(await screen.findByText('RS-2026-00005')).toBeInTheDocument();
    expect(screen.getByText('RS-2026-00004')).toBeInTheDocument();
    expect(screen.getByText('Screened — pending review')).toBeInTheDocument();
    expect((await screen.findAllByText('Reviewed')).length).toBeGreaterThanOrEqual(2);
  });
});