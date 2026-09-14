/**
 * Screening flow · case creation + image upload validation
 * (requirements: create a case, client-side image validation, wiring of
 * createCase → screenCase).
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, within, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { CreateCaseRequest } from '../src/api/types';

const api = vi.hoisted(() => ({
  createCase: vi.fn(),
  screenCase: vi.fn(),
  getCase: vi.fn(),
  listCases: vi.fn(async () => []),
  fetchCaseImage: vi.fn(async () => new Blob()),
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
  submitReview: api.submitReview,
  fetchReport: api.fetchReport,
  fetchHealth: api.fetchHealth,
}));

import { NewScreeningPage } from '../src/pages/NewScreeningPage';

const successCase = {
  caseId: 'RS-TEST-1',
  status: 'completed',
  quality: { class: 'good', score: 0.92, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
  aiPrediction: { grade: 2, gradeLabel: 'Moderate NPDR', referable: true, confidence: 0.81, uncertainty: 0.11, reviewRequired: false },
  explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
  humanReview: null,
  finalDecision: null,
};

function jpegFile(name = 'scan.jpg', size = 1024): File {
  return new File([new Uint8Array(size)], name, { type: 'image/jpeg' });
}

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';
});

describe('NewScreeningPage — case creation', () => {
  it('creates a case then screens it, then routes to the case view', async () => {
    api.createCase.mockResolvedValue({ caseId: 'RS-TEST-1', status: 'created' });
    api.screenCase.mockResolvedValue(successCase);
    const user = userEvent.setup();

    render(<NewScreeningPage />);

    await user.type(screen.getByPlaceholderText('Opaque patient token, no PII'), 'PT-1004');
    await user.selectOptions(screen.getByLabelText('Eye'), 'OS');

    const upload = screen.getByLabelText(/Fundus image/i);
    await user.upload(upload, jpegFile());

    const userForm = screen.getByLabelText('PHC id');
    await user.type(userForm, 'PHC-7');

    await user.click(screen.getByRole('button', { name: 'Run screening' }));

    const expectedMeta: CreateCaseRequest = { patientId: 'PT-1004', eye: 'OS', phcId: 'PHC-7' };
    await vi.waitFor(() => expect(api.createCase).toHaveBeenCalledWith(expectedMeta));
    expect(api.screenCase).toHaveBeenCalledWith('RS-TEST-1', expect.any(File), expectedMeta);

    await vi.waitFor(() => expect(window.location.hash).toBe('#/case/RS-TEST-1'));
  });
});

describe('NewScreeningPage — image upload validation (client-side, mirrors backend)', () => {
  it('rejects an unsupported file type before any API call', async () => {
    const user = userEvent.setup();
    render(<NewScreeningPage />);

    await user.type(screen.getByPlaceholderText('Opaque patient token, no PII'), 'PT-1');
    const upload = screen.getByLabelText(/Fundus image/i);
    // fireEvent bypasses the accept-attribute filter on purpose: we must be
    // able to select an unsupported file to prove the validation rejects it.
    fireEvent.change(upload, {
      target: { files: [new File(['nope'], 'scan.txt', { type: 'text/plain' })] },
    });

    await user.click(screen.getByRole('button', { name: 'Run screening' }));

    expect(await screen.findByText(/Unsupported file type/i)).toBeInTheDocument();
    expect(api.createCase).not.toHaveBeenCalled();
    expect(api.screenCase).not.toHaveBeenCalled();
  });

  it('rejects submission without a selected image', async () => {
    const user = userEvent.setup();
    render(<NewScreeningPage />);

    await user.type(screen.getByPlaceholderText('Opaque patient token, no PII'), 'PT-1');
    await user.click(screen.getByRole('button', { name: 'Run screening' }));

    expect(await screen.findByText(/Please select a fundus image/i)).toBeInTheDocument();
    expect(api.createCase).not.toHaveBeenCalled();
  });

  it('rejects an oversized image', async () => {
    const user = userEvent.setup();
    render(<NewScreeningPage />);

    await user.type(screen.getByPlaceholderText('Opaque patient token, no PII'), 'PT-1');
    const upload = screen.getByLabelText(/Fundus image/i);
    fireEvent.change(upload, {
      target: { files: [jpegFile('big.jpg', 21 * 1024 * 1024)] },
    });

    await user.click(screen.getByRole('button', { name: 'Run screening' }));

    expect(await screen.findByText(/Max allowed size is 20 MB/i)).toBeInTheDocument();
    expect(api.createCase).not.toHaveBeenCalled();
  });

  it('shows a preview thumbnail for a valid image selection', async () => {
    const user = userEvent.setup();
    render(<NewScreeningPage />);

    const upload = screen.getByLabelText(/Fundus image/i);
    await user.upload(upload, jpegFile());

    const preview = await screen.findByAltText('Selected fundus image preview');
    expect(preview).toBeInTheDocument();
    expect(preview).toHaveAttribute('src', expect.stringMatching(/^data:image\/jpeg;base64,/));

    // No premature validation error in a valid state
    const form = screen.getByRole('form');
    expect(within(form).queryByRole('alert')).not.toBeInTheDocument();
  });
});