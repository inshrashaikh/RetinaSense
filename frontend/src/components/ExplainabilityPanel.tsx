/**
 * Explainability section. When the backend reports a Grad-CAM / evidence
 * artifact, its availability (and backend path, if present) is shown textually.
 * The frontend NEVER draws or fabricates medical evidence.
 */
import type { Explainability } from '../api/types';
import { Badge } from './ui/Badge';
import { Card, CardBody, CardHeader } from './ui/Card';

export function ExplainabilityPanel({ explain }: { explain: Explainability }) {
  const hasAny = explain.gradCamAvailable || explain.evidenceAvailable;

  return (
    <Card aria-label="Explainability">
      <CardHeader
        title="Explainability"
        subtitle="Model evidence · reported only when produced"
        icon="scan"
        bordered
        actions={
          <Badge tone={hasAny ? 'info' : 'neutral'} icon={hasAny ? 'checkCircle' : 'alert'}>
            {hasAny ? 'Artifacts available' : 'None produced'}
          </Badge>
        }
      />
      <CardBody>
        {!hasAny ? (
          <div className="block" role="note">
            <p className="block__title">Evidence unavailable.</p>
            <p className="note-text">
              No Grad-CAM attention map and no lesion-evidence overlay were produced for
              this image by the backend. The frontend does not draw or invent attention
              or evidence overlays — it only shows what the pipeline returns.
            </p>
          </div>
        ) : (
          <div className="block">
            <ul className="plain-list">
              {explain.gradCamAvailable && (
                <li>
                  Grad-CAM attention available
                  {explain.gradCamPath ? (
                    <>
                      {' '}
                      (backend artifact: <span className="mono">{explain.gradCamPath}</span>)
                    </>
                  ) : (
                    ''
                  )}
                </li>
              )}
              {explain.evidenceAvailable && (
                <li>
                  Lesion evidence overlay available
                  {explain.evidencePath ? (
                    <>
                      {' '}
                      (backend artifact: <span className="mono">{explain.evidencePath}</span>)
                    </>
                  ) : (
                    ''
                  )}
                </li>
              )}
            </ul>
            <p className="note-text">
              Grad-CAM represents model attention — not proof of causality. Artifact paths
              are backend file locations and are not served over HTTP in this prototype.
            </p>
          </div>
        )}
      </CardBody>
    </Card>
  );
}
