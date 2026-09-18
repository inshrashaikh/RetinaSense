/**
 * Auth gate — login flow, session persistence, role-based access and logout.
 *
 * Uses the REAL session module (localStorage) so login/logout transitions are
 * exercised end-to-end through the App auth gate.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

const api = vi.hoisted(() => ({
  login: vi.fn(),
  createCase: vi.fn(),
  screenCase: vi.fn(),
  getCase: vi.fn(),
  listCases: vi.fn(async () => []),
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
import { saveSession } from '../src/auth/session';

beforeEach(() => {
  vi.clearAllMocks();
  window.localStorage.clear();
  window.location.hash = '';

  api.fetchHealth.mockResolvedValue({ status: 'ok', matlabEngine: false, version: '0.1.0', database: 'ok' });
  api.fetchCaseStats.mockResolvedValue({
    totalCases: 0,
    screeningsCompleted: 0,
    pendingReviews: 0,
    recaptureRequired: 0,
    reviewed: 0,
    created: 0,
  });
});

describe('auth gate', () => {
  it('shows the login screen instead of the console when unauthenticated', () => {
    window.location.hash = '#/dashboard';
    render(<App />);

    expect(screen.getByRole('heading', { name: 'Sign in' })).toBeInTheDocument();
    expect(screen.getByLabelText('Username')).toBeInTheDocument();
    expect(screen.getByLabelText('Password')).toBeInTheDocument();
    expect(screen.queryByText('RetinaSense screening console')).not.toBeInTheDocument();
  });

  it('stores the token and opens the dashboard after a successful login', async () => {
    const user = userEvent.setup();
    api.login.mockResolvedValue({
      token: 'signed-token',
      user: { id: 1, username: 'doctor', name: 'Dr. Meera Rao', role: 'ophthalmologist' },
    });

    window.location.hash = '#/login';
    render(<App />);

    await user.type(screen.getByLabelText('Username'), 'doctor');
    await user.type(screen.getByLabelText('Password'), 'doctor123');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(api.login).toHaveBeenCalledWith('doctor', 'doctor123');
    // An ophthalmologist lands on the clinical review dashboard.
    expect(await screen.findByRole('heading', { name: 'Clinical review' })).toBeInTheDocument();
    expect(screen.getByText('Dr. Meera Rao')).toBeInTheDocument();
  });

  it('shows an honest error and stays on the login page when credentials are wrong', async () => {
    const user = userEvent.setup();
    api.login.mockRejectedValue({
      kind: 'http',
      code: 'UNAUTHORIZED',
      message: 'Invalid username or password. Please check your credentials and try again.',
      httpStatus: 401,
      stage: 'auth',
    });

    window.location.hash = '#/login';
    render(<App />);

    await user.type(screen.getByLabelText('Username'), 'doctor');
    await user.type(screen.getByLabelText('Password'), 'wrong');
    await user.click(screen.getByRole('button', { name: 'Sign in' }));

    expect(await screen.findByText(/Invalid username or password/i)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Sign in' })).toBeInTheDocument();
  });

  it('signing out clears the session and returns to the public site', async () => {
    saveSession('token', { id: 1, username: 'doctor', name: 'Dr. Meera Rao', role: 'ophthalmologist' });
    window.location.hash = '#/dashboard';

    const user = userEvent.setup();
    render(<App />);

    expect(await screen.findByRole('heading', { name: 'Clinical review' })).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Sign out' }));

    expect(await screen.findByRole('heading', { level: 1, name: /Smarter retinal screening/i })).toBeInTheDocument();
    expect(window.localStorage.getItem('retinasense_token')).toBeNull();
  });
});

describe('role-based access', () => {
  it('redirects a capture-only operator away from the review queue', async () => {
    saveSession('token', { id: 2, username: 'operator', name: 'PHC Operator', role: 'phc_operator' });
    window.location.hash = '#/review';

    render(<App />);

    // The operator is sent to their own operations dashboard, which has no
    // review controls.
    expect(
      await screen.findByRole('heading', { name: 'Screening operations' }),
    ).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Review queue' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Review queue' })).not.toBeInTheDocument();
  });

  it('lets an ophthalmologist open the review queue', async () => {
    saveSession('token', { id: 1, username: 'doctor', name: 'Dr. Meera Rao', role: 'ophthalmologist' });
    window.location.hash = '#/review';

    render(<App />);

    expect(await screen.findByRole('heading', { name: 'Review queue' })).toBeInTheDocument();
  });
});