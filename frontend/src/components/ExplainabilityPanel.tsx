/**
 * Explainability section. When the backend produces a REAL Grad-CAM attention
 * map (and/or lesion-evidence overlay), the backend returns gradCamPath/
 * evidencePath and serves the PNGs over HTTP under /api/cases/{caseId}/
 * artifacts/{name}. This panel fetches and displays EXACTLY the artifact the
 * backend produced.
 *
 * The frontend NEVER draws or invents attention or evidence — if the backend
 * reports none, the panel shows an honest empty state and never a fabricated
 * map.
 */
import { useEffect, useState } from 'react';
import { fetchCaseArtifact } from '../api/endpoints';
import type { Explainability } from '../api/types';
import { Badge } from './ui/Badge';
import { Card, CardBody, CardHeader } from './ui/Card';

type ArtifactState = 'loading' | 'done' | 'unavailable';

function ArtifactFigure({ caseId, name }: { caseId: string; name: string }) {
  const [src, setSrc] = useState<string | null>(null);
  const [state, setState] = useState<ArtifactState>('loading');

  useEffect(() => {
    let objectUrl: string | null = null;
    let cancelled = false;

    fetchCaseArtifact(caseId, name)
      .then((blob) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
        setState('done');
      })
      .catch(() => {
        if (cancelled) return;
        setState('unavailable');
      });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [caseId, name]);

  if (state === 'done' && src) {
    return (
      <figure className="artifact-figure" role="img" aria-label="Model attention map">
        <img src={src} alt="Model attention map (Grad-CAM). Not proof of causality." />
        <figcaption>Model attention — not proof of causality.</figcaption>
      </figure>
    );
  }

  if (state === 'unavailable') {
    return (
      <p className="note-text" role="note">
        The backend served no artifact image. Attention is never drawn here.
      </p>
    );
  }

  return (
    <p className="note-text" role="status">
      Loading attention artifact…
    </p>
  );
}

export function ExplainabilityPanel({ caseId, explain }: { caseId: string; explain: Explainability }) {
  const gradCamName = explain.gradCamPath?.split('/').pop() ?? null;
  const evidenceName = explain.evidencePath?.split('/').pop() ?? null;
  const hasAny = explain.gradCamAvailable || explain.evidenceAvailable;

  return (
    <Card aria-label="Explainability">
      <CardHeader
        title="Explainability"
        subtitle="Model evidence — only what the pipeline actually produced"
        icon="scan"
        actions={
          <Badge tone={hasAny ? 'info' : 'neutral'} icon={hasAny ? 'checkCircle' : 'alert'}>
            {hasAny ? 'Artifacts available' : 'None produced'}
          </Badge>
        }
      />
      <CardBody>
        {!hasAny ? (
          <p className="note-text">
            Evidence unavailable — the backend produced no Grad-CAM attention map
            and no lesion-evidence overlay for this image. The frontend does not
            draw or invent attention; it only shows what the pipeline returns.
          </p>
        ) : (
          <ul className="plain-list">
            {explain.gradCamAvailable && gradCamName && (
              <li>
                <strong>Grad-CAM attention</strong> —{' '}
                <ArtifactFigure caseId={caseId} name={gradCamName} />
              </li>
            )}
            {explain.evidenceAvailable && evidenceName && (
              <li>
                <strong>Lesion evidence overlay</strong> —{' '}
                <ArtifactFigure caseId={caseId} name={evidenceName} />
              </li>
            )}
          </ul>
        )}
        <p className="note-text">
          Grad-CAM represents model attention — not proof of causality. Artifact
          PNGs are served by the backend artifact endpoint and are shown only
          when the pipeline produced them.
        </p>
      </CardBody>
    </Card>
  );
}
