/**
 * API error states — backend unreachable, engine unavailable, case not found.
 * The UI must surface honest, friendly errors and never fabricate a result.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

const api = vi.hoisted(() => ({
  createCase: vi.fn(),
  screenCase: vi.fn(),
  getCase: vi.fn(),
  listCases: vi.fn(async () => []),
  fetchCaseImage: vi.fn(async () => new Blob()),
  fetchCaseArtifact: vi.fn(async () => new Blob()),
  submitReview: vi.fn(),
  fetchReport: vi.fn(),
  fetchHealth: vi.fn(),
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
}));

import { NewScreeningPage } from '../src/pages/NewScreeningPage';
import { CaseViewPage } from '../src/pages/CaseViewPage';

function jpegFile(name = 'scan.jpg'): File {
  return new File([new Uint8Array(1024)], name, { type: 'image/jpeg' });
}

function engineError(message = 'MATLAB engine is not connected.'): never {
  throw { kind: 'http', code: 'MATLAB_ENGINE_UNAVAILABLE', message, httpStatus: 503 };
}

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';
});

describe('API error states', () => {
  it('shows a friendly "engine unavailable" error when the MATLAB engine is down', async () => {
    api.createCase.mockResolvedValue({ caseId: 'RS-E1', status: 'created' });
    api.screenCase.mockImplementation(() => engineError());
    const user = userEvent.setup();

    render(<NewScreeningPage />);
    await user.type(screen.getByPlaceholderText('Opaque patient token, no PII'), 'PT-1');
    await user.upload(screen.getByLabelText(/Fundus image/i), jpegFile());
    await user.click(screen.getByRole('button', { name: 'Run screening' }));

    expect(await screen.findByText('Screening engine unavailable')).toBeInTheDocument();
    expect(screen.getByText(/no result was fabricated/i)).toBeInTheDocument();
    // No navigation happened — the user stays on the form.
    expect(window.location.hash).not.toContain('#/case/');
  });

  it('shows a network error banner when the backend is unreachable during screening', async () => {
    api.createCase.mockImplementation(() => {
      throw { kind: 'network', code: 'NETWORK_ERROR', message: 'Cannot reach the RetinaSense backend.' };
    });
    const user = userEvent.setup();

    render(<NewScreeningPage />);
    await user.type(screen.getByPlaceholderText('Opaque patient token, no PII'), 'PT-1');
    await user.upload(screen.getByLabelText(/Fundus image/i), jpegFile());
    await user.click(screen.getByRole('button', { name: 'Run screening' }));

    expect(await screen.findByText('Backend unreachable')).toBeInTheDocument();
    expect(screen.getByText(/please check that it is running/i)).toBeInTheDocument();
  });

  it('shows "Case not found" and a back action for an unknown case', async () => {
    api.getCase.mockImplementation(() => {
      throw { kind: 'http', code: 'CASE_NOT_FOUND', message: 'No such case.', httpStatus: 404 };
    });

    render(<CaseViewPage caseId="RS-NOPE" />);

    expect(await screen.findByText('Case not found')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Back to dashboard' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument();
    // Nothing resembling a grade is invented.
    expect(screen.queryByText(/Moderate NPDR/i)).not.toBeInTheDocument();
  });
});