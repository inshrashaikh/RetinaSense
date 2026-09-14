/**
 * Human-in-the-loop review — override workflow and AI immutability.
 * After a human override the FINAL decision changes while the AI prediction
 * panel keeps the original value verbatim.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { CaseResponse, ReviewRequest } from '../src/api/types';

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

import { CaseViewPage } from '../src/pages/CaseViewPage';

/** Shared mutable case: humanReview/finalDecision are only written by the review. */
const mutableCase: CaseResponse = {
  caseId: 'RS-REVIEW-1',
  status: 'completed',
  quality: { class: 'good', score: 0.9, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
  aiPrediction: { grade: 2, gradeLabel: 'Moderate NPDR', referable: true, confidence: 0.6, uncertainty: 0.3, reviewRequired: true },
  explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
  humanReview: null,
  finalDecision: null,
};

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';
  mutableCase.humanReview = null;
  mutableCase.finalDecision = null;
  mutableCase.aiPrediction = {
    grade: 2, gradeLabel: 'Moderate NPDR', referable: true,
    confidence: 0.6, uncertainty: 0.3, reviewRequired: true,
  };

  api.getCase.mockImplementation(async () => {
    // return a copy so the panel re-renders with current fields
    return JSON.parse(JSON.stringify(mutableCase)) as CaseResponse;
  });

  api.submitReview.mockImplementation(async (caseId: string, review: ReviewRequest) => {
    const overrideGrade = review.overrideGrade ?? mutableCase.aiPrediction?.grade ?? null;
    mutableCase.humanReview = {
      action: review.action,
      reviewerId: review.reviewerId,
      overrideGrade,
      finalReferral: overrideGrade !== null && overrideGrade >= 2,
      status: 'overridden',
      notes: review.notes ?? '',
      timestamp: new Date().toISOString(),
    };
    mutableCase.finalDecision = {
      grade: overrideGrade,
      gradeLabel: 'Severe NPDR',
      referral: overrideGrade !== null && overrideGrade >= 2,
    };
    return {
      caseId,
      review: mutableCase.humanReview,
      finalDecision: mutableCase.finalDecision,
    };
  });
});

describe('Human override workflow', () => {
  it('records an override as the final decision with reviewer id and notes', async () => {
    const user = userEvent.setup();
    render(<CaseViewPage caseId="RS-REVIEW-1" />);

    await screen.findByText(/2 · Moderate NPDR/i);
    const submit = screen.getByRole('button', { name: 'Submit review' });

    await user.click(screen.getByLabelText('Override grade'));

    const gradeSelect = screen.getByLabelText('Override DR grade');
    await user.selectOptions(gradeSelect, '3');

    await user.type(screen.getByLabelText('Reviewer (ophthalmologist) ID'), 'OPH-3');
    await user.type(screen.getByLabelText('Notes'), 'Confirmed clinically; upgrading.');

    await user.click(submit);

    expect(api.submitReview).toHaveBeenCalledWith('RS-REVIEW-1', {
      action: 'override',
      reviewerId: 'OPH-3',
      overrideGrade: 3,
      notes: 'Confirmed clinically; upgrading.',
    });

    expect(await screen.findByText(/Review recorded\./)).toBeInTheDocument();

    // Final decision reflects the override.
    expect(await screen.findByText(/3 · Severe NPDR/i)).toBeInTheDocument();
    expect(screen.getByText('Refer to ophthalmologist')).toBeInTheDocument();
    expect(screen.getByText('override')).toBeInTheDocument();
  });

  it('keeps the AI prediction immutable after the human override', async () => {
    const user = userEvent.setup();
    render(<CaseViewPage caseId="RS-REVIEW-1" />);

    await screen.findByText(/2 · Moderate NPDR/i);
    await user.click(screen.getByLabelText('Override grade'));
    const gradeSelect = screen.getByLabelText('Override DR grade');
    await user.selectOptions(gradeSelect, '3');
    await user.type(screen.getByLabelText('Reviewer (ophthalmologist) ID'), 'OPH-3');
    await user.click(screen.getByRole('button', { name: 'Submit review' }));

    // Final decision is the override…
    expect(await screen.findByText(/3 · Severe NPDR/i)).toBeInTheDocument();

    // …but the AI prediction section (original, immutable) still shows 2.
    const aiSection = screen.getByRole('region', { name: 'AI prediction' });
    expect(within(aiSection).getByText(/2 · Moderate NPDR/i)).toBeInTheDocument();

    // The UI calls out the divergence explicitly (numbers are split across
    // <strong> nodes, so assert on the section's text content).
    const finalSection = await screen.findByRole('region', { name: 'Final decision' });
    expect(finalSection.textContent).toContain('differs from the AI grade (2)');
    expect(finalSection.textContent).toContain('final grade (3)');
  });
});