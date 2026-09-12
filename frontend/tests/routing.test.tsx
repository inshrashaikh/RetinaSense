/**
 * Routing — `#/` is the public landing page, `#/dashboard` is the console, and
 * dynamic case/report paths keep working. Also covers the app shell navigation
 * and section-anchor handling.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

const api = vi.hoisted(() => ({
  createCase: vi.fn(),
  screenCase: vi.fn(),
  getCase: vi.fn(),
  listCases: vi.fn(),
  fetchCaseImage: vi.fn(),
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
  submitReview: api.submitReview,
  fetchReport: api.fetchReport,
  fetchHealth: api.fetchHealth,
  fetchCaseStats: api.fetchCaseStats,
  generateReport: api.generateReport,
}));

import App from '../src/App';
import { AppShell } from '../src/components/AppShell';
import { getHashPath, getSectionAnchor } from '../src/router';

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';
  api.listCases.mockResolvedValue([]);
  api.fetchCaseImage.mockResolvedValue(new Blob());
  api.fetchHealth.mockResolvedValue({ status: 'ok', matlabEngine: true, version: '0.1.0', database: 'ok' });
  api.fetchCaseStats.mockResolvedValue({
    totalCases: 0,
    screeningsCompleted: 0,
    pendingReviews: 0,
    recaptureRequired: 0,
    reviewed: 0,
    created: 0,
  });
});

describe('router', () => {
  it('treats landing section anchors as the landing route', () => {
    window.location.hash = '#how-it-works';
    expect(getHashPath()).toBe('/');
    expect(getSectionAnchor()).toBe('how-it-works');

    window.location.hash = '#/dashboard';
    expect(getHashPath()).toBe('/dashboard');
    expect(getSectionAnchor()).toBeNull();
  });
});

describe('App routing', () => {
  it('renders the public landing page at #/', async () => {
    window.location.hash = '#/';
    render(<App />);
    expect(screen.getByRole('heading', { level: 1, name: /Smarter retinal screening/i })).toBeInTheDocument();
    expect(screen.queryByText('RetinaSense screening console')).not.toBeInTheDocument();
    await screen.findByText('Total cases');
  });

  it('renders the dashboard inside the app shell at #/dashboard', async () => {
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(screen.getByText('RetinaSense screening console')).toBeInTheDocument();
    // The shell — not the landing navbar — wraps application pages.
    expect(screen.getByRole('navigation', { name: 'Application navigation' })).toBeInTheDocument();
    expect(await screen.findByText('Recent cases')).toBeInTheDocument();
    await screen.findAllByText(/Backend reachable/);
  });

  it('keeps the create-case and upload routes for an existing case', async () => {
    window.location.hash = '#/cases/new';
    const { unmount } = render(<App />);
    expect(screen.getByRole('heading', { name: 'Create case' })).toBeInTheDocument();
    await screen.findByText(/Backend reachable/);
    unmount();

    window.location.hash = '#/case/RS-2026-00001/upload';
    render(<App />);
    expect(screen.getByRole('heading', { name: 'Upload fundus image' })).toBeInTheDocument();
    // The dynamic path parser still resolves the case id.
    expect(screen.getAllByText(/RS-2026-00001/).length).toBeGreaterThan(0);
    await screen.findByText(/Backend reachable/);
  });

  it('renders every documented route without crashing', async () => {
    const caseRecord = {
      caseId: 'RS-1',
      status: 'completed',
      quality: { class: 'good', score: 0.9, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
      aiPrediction: { grade: 1, gradeLabel: 'Mild NPDR', referable: false, confidence: 0.7, uncertainty: 0.2, reviewRequired: false },
      explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
      humanReview: null,
      finalDecision: null,
    };
    api.getCase.mockResolvedValue(caseRecord);
    api.generateReport.mockResolvedValue({ caseId: 'RS-1', report: null, summary: null, disclaimer: null });

    const routes: { hash: string; heading: RegExp; settled: RegExp }[] = [
      { hash: '#/screening', heading: /^New screening$/, settled: /^Run screening$/ },
      { hash: '#/cases', heading: /^Cases$/, settled: /No screenings have been run/i },
      { hash: '#/cases/new', heading: /^Create case$/, settled: /Case details/ },
      { hash: '#/result', heading: /^Screening result$/, settled: /^No result yet$/ },
      { hash: '#/review', heading: /^Review queue$/, settled: /Nothing to review/ },
      { hash: '#/reports', heading: /^Reports$/, settled: /No reports yet/ },
      { hash: '#/case/RS-1', heading: /^Case RS-1$/, settled: /Case information/ },
      { hash: '#/case/RS-1/upload', heading: /^Upload fundus image$/, settled: /One image per case/i },
      { hash: '#/reports/RS-1', heading: /Screening report · RS-1/, settled: /Case information/ },
    ];

    for (const route of routes) {
      window.location.hash = route.hash;
      const { unmount } = render(<App />);
      expect(screen.getByRole('heading', { name: route.heading })).toBeInTheDocument();
      await screen.findByText(route.settled);
      await screen.findByText(/Backend reachable/);
      unmount();
    }
  });

  it('shows the 404 state for an unknown route with a way back', async () => {
    window.location.hash = '#/does-not-exist';
    render(<App />);
    expect(screen.getByRole('heading', { name: 'Page not found' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Go to dashboard' })).toBeInTheDocument();
    await screen.findByText(/Backend reachable/);
  });
});

describe('AppShell', () => {
  it('marks the active navigation item and groups the destinations', async () => {
    window.location.hash = '#/cases';
    render(
      <AppShell demoMode={false}>
        <p>content</p>
      </AppShell>,
    );
    await screen.findByText(/Backend reachable/);

    expect(screen.getByRole('link', { name: 'Cases' })).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('link', { name: 'Dashboard' })).not.toHaveAttribute('aria-current');
    for (const label of ['New screening', 'Latest result', 'Review queue', 'Reports']) {
      expect(screen.getByRole('link', { name: label })).toBeInTheDocument();
    }
  });

  it('opens and closes the mobile navigation drawer', async () => {
    window.location.hash = '#/dashboard';
    const user = userEvent.setup();
    const { container } = render(
      <AppShell demoMode={false}>
        <p>content</p>
      </AppShell>,
    );

    await screen.findByText(/Backend reachable/);
    const toggle = screen.getByRole('button', { name: 'Open navigation' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');

    await user.click(toggle);
    const close = screen.getByRole('button', { name: 'Close navigation' });
    expect(close).toHaveAttribute('aria-expanded', 'true');
    expect(container.querySelector('.shell--nav-open')).not.toBeNull();

    await user.click(close);
    expect(container.querySelector('.shell--nav-open')).toBeNull();
  });

  it('shows the demo banner whenever demo mode is active', async () => {
    window.location.hash = '#/dashboard';
    render(
      <AppShell demoMode>
        <p>content</p>
      </AppShell>,
    );
    expect(screen.getByText(/DEMO MODE — SIMULATED DATA/)).toBeInTheDocument();
    await screen.findByText(/Backend reachable/);
  });
});
