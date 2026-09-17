/**
 * Report detail PDF errors — a failed PDF download must be surfaced even when
 * the report itself loaded fine (regression: the alert used to be gated on
 * `!report`, silently swallowing download failures). The PDF failure is a
 * separate state from report-generation failure.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { CaseResponse, ReportResponse } from '../src/api/types';

const api = vi.hoisted(() => ({
  getCase: vi.fn(),
  generateReport: vi.fn(),
  fetchReportPdf: vi.fn(),
  fetchCaseImage: vi.fn(async () => new Blob()),
  fetchCaseArtifact: vi.fn(async () => new Blob()),
  createCase: vi.fn(),
  screenCase: vi.fn(),
  listCases: vi.fn(async () => []),
  submitReview: vi.fn(),
  fetchHealth: vi.fn(),
}));

vi.mock('../src/api/endpoints', () => ({
  isDemoMode: false,
  getCase: api.getCase,
  generateReport: api.generateReport,
  fetchReportPdf: api.fetchReportPdf,
  fetchCaseImage: api.fetchCaseImage,
  fetchCaseArtifact: api.fetchCaseArtifact,
  createCase: api.createCase,
  screenCase: api.screenCase,
  listCases: api.listCases,
  submitReview: api.submitReview,
  fetchHealth: api.fetchHealth,
}));

import { ReportDetailPage } from '../src/pages/ReportDetailPage';

const successCase: CaseResponse = {
  caseId: 'RS-RPT-1',
  status: 'completed',
  quality: { class: 'good', score: 0.9, failureReasons: [] },
  aiPrediction: {
    grade: 2,
    gradeLabel: 'Moderate NPDR',
    probabilities: null,
    referable: true,
    confidence: 0.6,
    uncertainty: 0.3,
    reviewRequired: true,
  },
  explainability: {
    gradCamAvailable: false,
    gradCamPath: null,
    evidenceAvailable: false,
    evidencePath: null,
  },
  humanReview: null,
  finalDecision: null,
};

const reportRes: ReportResponse = {
  caseId: 'RS-RPT-1',
  report: {
    caseId: 'RS-RPT-1',
    status: 'completed',
    quality: successCase.quality,
    aiPrediction: successCase.aiPrediction,
    explainability: successCase.explainability,
  },
  summary: 'Full narrative assembled by the reporting stage.',
  disclaimer: 'Not a medical device.',
};

async function renderPage() {
  render(<ReportDetailPage caseId="RS-RPT-1" />);
  // The report must be loaded before the Download PDF button exists.
  await screen.findByText(/Full narrative assembled by the reporting stage/i);
}

beforeEach(() => {
  vi.clearAllMocks();
  api.getCase.mockResolvedValue(successCase);
  api.generateReport.mockResolvedValue(reportRes);
});

describe('ReportDetailPage PDF errors', () => {
  it('surfaces a PDF download failure even though the report loaded fine', async () => {
    api.fetchReportPdf.mockRejectedValue({
      kind: 'network',
      code: 'NETWORK_ERROR',
      message: 'Cannot reach the RetinaSense backend.',
    });

    await renderPage();

    await userEvent.click(screen.getByRole('button', { name: 'Download PDF' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Backend unreachable');
    expect(alert).toHaveTextContent('Try PDF download again');

    // The loaded report content is still visible — a PDF failure is an error
    // on top of a good report, never a blanked page.
    expect(
      screen.getByText(/Full narrative assembled by the reporting stage/i),
    ).toBeInTheDocument();
  });

  it('recovers when the PDF download is retried and finally succeeds', async () => {
    api.fetchReportPdf
      .mockRejectedValueOnce({ kind: 'http', code: 'INTERNAL_ERROR', message: 'boom' })
      .mockResolvedValueOnce(new Blob(['%PDF-1.4'], { type: 'application/pdf' }));

    await renderPage();

    await userEvent.click(screen.getByRole('button', { name: 'Download PDF' }));
    await screen.findByRole('alert');

    await userEvent.click(screen.getByRole('button', { name: 'Try PDF download again' }));

    await waitFor(() => {
      expect(screen.queryByText('Backend error')).not.toBeInTheDocument();
    });
    expect(api.fetchReportPdf).toHaveBeenCalledTimes(2);
  });
});