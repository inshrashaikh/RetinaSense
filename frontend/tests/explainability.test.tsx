/**
 * Explainability — the panel must show EXACTLY the artifact the backend
 * produced and keep the two failure modes apart:
 *   * 404 / ARTIFACT_UNAVAILABLE → the calm, honest "no artifact" state.
 *   * network error / 5xx → a real error alert, never a calm "no artifact".
 * The frontend never draws or invents attention when the backend reports none.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import type { Explainability } from '../src/api/types';

const api = vi.hoisted(() => ({
  fetchCaseArtifact: vi.fn(),
}));

vi.mock('../src/api/endpoints', () => ({
  isDemoMode: false,
  fetchCaseArtifact: api.fetchCaseArtifact,
}));

import { ExplainabilityPanel } from '../src/components/ExplainabilityPanel';

const withGradCam: Explainability = {
  gradCamAvailable: true,
  gradCamPath: '/generated/gradcam-rs-x1.png',
  evidenceAvailable: false,
  evidencePath: null,
};

const noneProduced: Explainability = {
  gradCamAvailable: false,
  gradCamPath: null,
  evidenceAvailable: false,
  evidencePath: null,
};

beforeEach(() => {
  vi.clearAllMocks();
});

describe('ExplainabilityPanel', () => {
  it('renders the artifact PNG the backend actually served', async () => {
    api.fetchCaseArtifact.mockResolvedValue(new Blob(['png-bytes'], { type: 'image/png' }));

    render(<ExplainabilityPanel caseId="RS-X1" explain={withGradCam} />);

    const figureImg = await screen.findByRole('img', {
      name: 'Model attention map (Grad-CAM). Not proof of causality.',
    });
    expect(figureImg).toBeInTheDocument();
    // setup.ts polyfills URL.createObjectURL → 'blob:mock-preview'.
    expect(figureImg).toHaveAttribute('src', 'blob:mock-preview');

    // The artifact name is derived from the backend-provided path.
    expect(api.fetchCaseArtifact).toHaveBeenCalledWith('RS-X1', 'gradcam-rs-x1.png');
  });

  it('shows an honest empty state on ARTIFACT_UNAVAILABLE (404), not an error', async () => {
    api.fetchCaseArtifact.mockRejectedValue({
      kind: 'http',
      code: 'ARTIFACT_UNAVAILABLE',
      message: 'no artifact stored',
      httpStatus: 404,
    });

    render(<ExplainabilityPanel caseId="RS-X1" explain={withGradCam} />);

    expect(await screen.findByText(/served no artifact image/i)).toBeInTheDocument();
    // A 404 is an honest "the pipeline produced nothing" — never styled as an error.
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(document.querySelector('.artifact-figure img')).toBeNull();
  });

  it('surfaces a network/API failure as a real error — never a calm "no artifact"', async () => {
    api.fetchCaseArtifact.mockRejectedValue({
      kind: 'network',
      code: 'NETWORK_ERROR',
      message: 'Cannot reach the RetinaSense backend.',
    });

    render(<ExplainabilityPanel caseId="RS-X1" explain={withGradCam} />);

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Backend unreachable');
    // The two states are NOT collapsed: a network error is actionable, while a
    // 404 means the pipeline honestly produced nothing.
    expect(screen.queryByText(/served no artifact image/i)).not.toBeInTheDocument();
    expect(document.querySelector('.artifact-figure img')).toBeNull();
  });

  it('never draws attention when the backend produced no artifact', async () => {
    render(<ExplainabilityPanel caseId="RS-X1" explain={noneProduced} />);

    expect(
      await screen.findByText(/Evidence unavailable/i),
    ).toBeInTheDocument();
    expect(screen.getByText(/does not draw or invent attention/i)).toBeInTheDocument();
    expect(api.fetchCaseArtifact).not.toHaveBeenCalled();
  });
});