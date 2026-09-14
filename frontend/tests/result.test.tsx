/**
 * Result rendering — quality gate gating (recapture) and full result view.
 * The ungradable image must never produce a grade or report.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';

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

import { CaseViewPage } from '../src/pages/CaseViewPage';

const goodCase = {
  caseId: 'RS-RESULT-1',
  status: 'completed',
  quality: { class: 'good', score: 0.92, failureReasons: [], recaptureReason: null, recaptureInstruction: null },
  aiPrediction: { grade: 2, gradeLabel: 'Moderate NPDR', referable: true, confidence: 0.81, uncertainty: 0.11, reviewRequired: false },
  explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
  humanReview: null,
  finalDecision: null,
};

const recaptureCase = {
  caseId: 'RS-RESULT-2',
  status: 'recapture_required',
  quality: {
    class: 'ungradable',
    score: 0.14,
    failureReasons: ['illumination', 'fovCoverage'],
    recaptureReason: 'LOW_ILLUMINATION',
    recaptureInstruction: 'Ensure adequate lighting and re-capture the fundus image.',
  },
  aiPrediction: { grade: null, gradeLabel: null, referable: null, confidence: null, uncertainty: null, reviewRequired: null },
  explainability: { gradCamAvailable: false, gradCamPath: null, evidenceAvailable: false, evidencePath: null },
  humanReview: null,
  finalDecision: null,
};

beforeEach(() => {
  vi.clearAllMocks();
  window.location.hash = '';
});

describe('CaseViewPage — result rendering', () => {
  it('renders quality class, AI grade, referable badge, confidence, and no fabricated explainability', async () => {
    api.getCase.mockResolvedValue(goodCase);

    render(<CaseViewPage caseId="RS-RESULT-1" />);

    expect(await screen.findByText(/2 · Moderate NPDR/i)).toBeInTheDocument();
    expect(screen.getByText('Good')).toBeInTheDocument();
    expect(screen.getByText('Referable')).toBeInTheDocument();
    expect(screen.getByText('81%')).toBeInTheDocument();
    // Explainability is honest: none produced.
    expect(screen.getByText(/Evidence unavailable/i)).toBeInTheDocument();
    // No fabricated evidence path or overlay.
    expect(screen.queryByText(/gradCamPath/i)).not.toBeInTheDocument();
    // The review form is offered because no human review exists yet.
    expect(await screen.findByRole('button', { name: 'Submit review' })).toBeInTheDocument();
  });
});

describe('CaseViewPage — quality gate gates', () => {
  it('ungradable image → recapture instruction, no AI grade, no report, no review', async () => {
    api.getCase.mockResolvedValue(recaptureCase);

    render(<CaseViewPage caseId="RS-RESULT-2" />);

    expect((await screen.findAllByText(/Recapture requested/i)).length).toBeGreaterThan(0);
    expect(screen.getByText('LOW_ILLUMINATION')).toBeInTheDocument();
    expect(screen.getByText(/Ensure adequate lighting and re-capture the fundus image/i)).toBeInTheDocument();

    // The AI panel says nothing was produced — no invented grade.
    expect(screen.getByText(/No AI prediction was produced/i)).toBeInTheDocument();
    expect(screen.queryByText(/Mild NPDR|Moderate NPDR/i)).not.toBeInTheDocument();

    // Final decision pending: no referral is made on an ungradable image.
    expect(screen.getByText(/No final decision yet/i)).toBeInTheDocument();
    expect(screen.queryByText(/Refer to ophthalmologist/i)).not.toBeInTheDocument();

    // Report not offered for an ungradable image; review not applicable.
    expect(screen.queryByRole('button', { name: 'Load report' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Submit review' })).not.toBeInTheDocument();
  });

  it('does not render a report button until the user asks for it on a completed case', async () => {
    api.getCase.mockResolvedValue(goodCase);
    render(<CaseViewPage caseId="RS-RESULT-1" />);
    expect(await screen.findByRole('button', { name: 'Load report' })).toBeInTheDocument();
  });
});

describe('CaseViewPage — real explainability artifacts', () => {
  it('renders the backend-served Grad-CAM and evidence images with honest labels', async () => {
    api.getCase.mockResolvedValue({
      ...goodCase,
      explainability: {
        gradCamAvailable: true,
        gradCamPath: '/api/cases/RS-RESULT-1/artifacts/gradcam',
        evidenceAvailable: true,
        evidencePath: '/api/cases/RS-RESULT-1/artifacts/evidence',
      },
    });

    render(<CaseViewPage caseId="RS-RESULT-1" />);

    expect(await screen.findByAltText(/Grad-CAM attention overlay/i)).toBeInTheDocument();
    expect(screen.getByAltText(/independent retinal lesion-evidence overlay/i)).toBeInTheDocument();
    // Distinction preserved: attention is not proof of causality.
    expect(screen.getByText(/NOT proof of causality/i)).toBeInTheDocument();
    // Evidence is advisory only and never affects grade/referral.
    expect(screen.getByText(/advisory only/i)).toBeInTheDocument();
    expect(screen.queryByText(/Evidence unavailable/i)).not.toBeInTheDocument();
  });

  it('shows a clear unavailable state rather than a broken image when serving fails', async () => {
    api.getCase.mockResolvedValue({
      ...goodCase,
      explainability: {
        gradCamAvailable: true,
        gradCamPath: '/api/cases/RS-RESULT-1/artifacts/gradcam',
        evidenceAvailable: false,
        evidencePath: null,
      },
    });
    api.fetchCaseArtifact.mockRejectedValue({
      kind: 'http',
      code: 'ARTIFACT_UNAVAILABLE',
      message: 'No gradcam artifact is stored for this case.',
      httpStatus: 404,
    });

    render(<CaseViewPage caseId="RS-RESULT-1" />);

    expect(await screen.findByText(/Grad-CAM attention unavailable/i)).toBeInTheDocument();
    // No broken <img> for the missing artifact.
    expect(screen.queryByAltText(/Grad-CAM attention overlay/i)).not.toBeInTheDocument();
  });

  it('stays honest when the backend reports no artifacts at all', async () => {
    api.getCase.mockResolvedValue(goodCase); // gradCamAvailable=false, paths null

    render(<CaseViewPage caseId="RS-RESULT-1" />);

    expect(await screen.findByText(/Evidence unavailable/i)).toBeInTheDocument();
    expect(screen.queryByAltText(/Grad-CAM attention overlay/i)).not.toBeInTheDocument();
    expect(screen.queryByAltText(/evidence overlay/i)).not.toBeInTheDocument();
    expect(api.fetchCaseArtifact).not.toHaveBeenCalled();
  });
});