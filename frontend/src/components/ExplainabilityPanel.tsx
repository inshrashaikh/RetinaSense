/**
 * Explainability section. When the backend reports a Grad-CAM / evidence
 * artifact, its availability (and backend path, if present) is shown textually.
 * The frontend NEVER draws or fabricates medical evidence.
 */
import type { Explainability } from '../api/types';

export function ExplainabilityPanel({ explain }: { explain: Explainability }) {
  const hasAny = explain.gradCamAvailable || explain.evidenceAvailable;

  return (
    <section className="panel" aria-label="Explainability">
      <h2 className="panel-title">Explainability</h2>

      {!hasAny ? (
        <div className="empty-note" role="note">
          <p>
            <strong>Evidence unavailable.</strong> No Grad-CAM attention map and no
            lesion-evidence overlay were produced for this image by the backend.
          </p>
          <p>The frontend does not draw or invent attention or evidence overlays —
            it only shows what the pipeline returns.</p>
        </div>
      ) : (
        <div className="panel-block">
          <ul className="plain-list">
            {explain.gradCamAvailable && (
              <li>
                Grad-CAM attention available
                {explain.gradCamPath ? ` (backend artifact: ${explain.gradCamPath})` : ''}
              </li>
            )}
            {explain.evidenceAvailable && (
              <li>
                Lesion evidence overlay available
                {explain.evidencePath ? ` (backend artifact: ${explain.evidencePath})` : ''}
              </li>
            )}
          </ul>
          <p className="note-text">
            Grad-CAM represents model attention — not proof of causality. Artifact
            paths are backend file locations and are not served over HTTP in this prototype.
          </p>
        </div>
      )}
    </section>
  );
}