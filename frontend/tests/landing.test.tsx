/**
 * Public landing page — hero (with the real hero video), stats read from the
 * backend, workflow/technology/feature/safety sections, CTA and footer.
 */
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

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

import { LandingPage } from '../src/pages/LandingPage';
import { DISCLAIMER } from '../src/components/DisclaimerFooter';

/**
 * The hero asks the server whether /hero-section.mp4 exists before trusting
 * media events; stub that probe so both the video and the fallback paths can
 * be exercised deterministically.
 */
function stubHeroAsset(available: boolean) {
  vi.stubGlobal(
    'fetch',
    vi.fn(() => Promise.resolve({ ok: available, status: available ? 200 : 404 })),
  );
}

async function findHeroVideo(): Promise<HTMLVideoElement> {
  return waitFor(() => {
    const video = document.querySelector('.l-hero__video');
    expect(video).not.toBeNull();
    return video as HTMLVideoElement;
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';
  stubHeroAsset(true);
  api.fetchCaseStats.mockResolvedValue({
    totalCases: 12,
    screeningsCompleted: 9,
    pendingReviews: 3,
    recaptureRequired: 2,
    reviewed: 6,
    created: 1,
  });
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('LandingPage', () => {
  it('renders the hero with the provided hero video, not the internal dashboard', async () => {
    render(<LandingPage demoMode={false} />);
    await screen.findByText('Total cases');

    expect(screen.getByRole('heading', { level: 1, name: /Smarter retinal screening/i })).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'Start screening' }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('button', { name: 'Open dashboard' }).length).toBeGreaterThan(0);

    // The internal dashboard must not be the landing experience.
    expect(screen.queryByText('RetinaSense screening console')).not.toBeInTheDocument();

    const video = await findHeroVideo();
    expect(video).toHaveAttribute('autoplay');
    expect(video).toHaveAttribute('loop');
    expect(video).toHaveAttribute('playsinline');
    expect(video).not.toHaveAttribute('controls');
    const source = video.querySelector('source');
    expect(source).toHaveAttribute('src', '/hero-section.mp4');
  });

  it('falls back to a designed panel when the hero asset is not served', async () => {
    stubHeroAsset(false);
    render(<LandingPage demoMode={false} />);
    await screen.findByText('Total cases');

    expect(await screen.findByText(/Retinal screening, end to end/i)).toBeInTheDocument();
    expect(document.querySelector('.l-hero__video')).toBeNull();
  });

  it('falls back when the video errors before decoding any frame', async () => {
    render(<LandingPage demoMode={false} />);
    await screen.findByText('Total cases');
    const video = await findHeroVideo();

    fireEvent.error(video);

    expect(await screen.findByText(/Retinal screening, end to end/i)).toBeInTheDocument();
    expect(document.querySelector('.l-hero__video')).toBeNull();
  });

  // Regression: a stray media event (e.g. an aborted load on re-render) must not
  // hide a hero video that has already decoded a frame.
  it('keeps a hero video that has already loaded when a stray error fires', async () => {
    render(<LandingPage demoMode={false} />);
    await screen.findByText('Total cases');
    const video = await findHeroVideo();

    fireEvent.loadedData(video);
    fireEvent.error(video);

    expect(document.querySelector('.l-hero__video')).not.toBeNull();
    expect(screen.queryByText(/Retinal screening, end to end/i)).not.toBeInTheDocument();
  });

  it('shows the workflow and safety sections with anchor navigation', async () => {
    render(<LandingPage demoMode={false} />);
    await screen.findByText('Total cases');

    expect(screen.getByRole('heading', { name: /A clinical workflow, not a black box/i })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Guardrails that are visible in the product/i })).toBeInTheDocument();

    const howLink = screen.getAllByRole('link', { name: 'How it works' })[0];
    expect(howLink).toHaveAttribute('href', '#how-it-works');
  });

  it('reports screening volume from the backend and keeps the disclaimer visible', async () => {
    render(<LandingPage demoMode={false} />);

    expect(await screen.findByText('12')).toBeInTheDocument();
    expect(screen.getByText('Pending reviews')).toBeInTheDocument();

    expect(screen.getAllByText(DISCLAIMER).length).toBeGreaterThan(0);
  });

  it('never invents statistics when the backend is unreachable', async () => {
    api.fetchCaseStats.mockRejectedValue({ kind: 'network', code: 'NETWORK_ERROR', message: 'down' });

    render(<LandingPage demoMode={false} />);

    expect(await screen.findByText(/Live statistics unavailable/i)).toBeInTheDocument();
    expect(screen.getByText(/Nothing is estimated in their place/i)).toBeInTheDocument();
  });

  it('labels simulated data in demo mode', async () => {
    render(<LandingPage demoMode />);
    await screen.findByText('Total cases');
    expect(screen.getByText(/DEMO MODE — SIMULATED DATA/)).toBeInTheDocument();
  });
});
