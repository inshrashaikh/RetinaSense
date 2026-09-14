/**
 * Explainability section — displays the REAL Grad-CAM attention overlay and
 * the independent retinal-evidence overlay produced by the backend pipeline.
 *
 * The frontend NEVER fabricates either image: it only renders what the
 * backend serves (fetchCaseArtifact).  Grad-CAM is explicitly labelled as
 * model attention, not causal proof; the evidence overlay is labelled as
 * independent/advisory and is never allowed to influence grade/referral.
 * Missing artifacts render as a clear text state — never a broken image.
 */
import { useEffect, useState } from 'react';
import { fetchCaseArtifact } from '../api/endpoints';
import type { Explainability } from '../api/types';
import { friendlyError } from '../utils/errors';

type LoadState = 'loading' | 'done' | 'unavailable';

function ArtifactImage({
  caseId,
  name,
  alt,
  label,
}: {
  caseId: string;
  name: 'gradcam' | 'evidence';
  alt: string;
  label: string;
}) {
  const [state, setState] = useState<LoadState>('loading');
  const [src, setSrc] = useState<string | null>(null);
  const [detail, setDetail] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    let objectUrl: string | null = null;

    setState('loading');
    setDetail(null);
    fetchCaseArtifact(caseId, name)
      .then((blob) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
        setState('done');
      })
      .catch((err) => {
        if (cancelled) return;
        setDetail(friendlyError(err).detail);
        setState('unavailable');
      });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [caseId, name]);

  return (
    <div className="panel-block">
      <p>
        <strong>{label}</strong>
      </p>
      {state === 'done' && src ? (
        <img className="fundus-img artifact-img" src={src} alt={alt} />
      ) : state === 'unavailable' ? (
        <div className="image-placeholder" role="note">
          <p>
            <strong>{label} unavailable</strong>
          </p>
          <p>{detail ?? 'The backend could not serve this artifact.'}</p>
        </div>
      ) : (
        <div className="image-placeholder" aria-label={`Loading ${label}`}>
          <p>Loading {label.toLowerCase()}…</p>
        </div>
      )}
    </div>
  );
}

export function ExplainabilityPanel({
  caseId,
  explain,
}: {
  caseId: string;
  explain: Explainability;
}) {
  const hasGradCam = explain.gradCamAvailable && Boolean(explain.gradCamPath);
  const hasEvidence = explain.evidenceAvailable && Boolean(explain.evidencePath);

  if (!hasGradCam && !hasEvidence) {
    return (
      <section className="panel" aria-label="Explainability">
        <h2 className="panel-title">Explainability</h2>
        <div className="empty-note" role="note">
          <p>
            <strong>Evidence unavailable.</strong> No Grad-CAM attention map and no
            lesion-evidence overlay were produced for this image by the backend.
          </p>
          <p>The frontend does not draw or invent attention or evidence overlays —
            it only shows what the pipeline returns.</p>
        </div>
      </section>
    );
  }

  return (
    <section className="panel" aria-label="Explainability">
      <h2 className="panel-title">Explainability</h2>

      {hasGradCam && (
        <ArtifactImage
          caseId={caseId}
          name="gradcam"
          label="Grad-CAM attention"
          alt={`Grad-CAM attention overlay for case ${caseId}`}
        />
      )}

      {hasEvidence && (
        <ArtifactImage
          caseId={caseId}
          name="evidence"
          label="Retinal evidence overlay"
          alt={`Independent retinal lesion-evidence overlay for case ${caseId}`}
        />
      )}

      <div className="panel-block">
        <ul className="plain-list">
          {hasGradCam && (
            <li>
              <strong>Grad-CAM</strong> is model attention on the decision class — NOT
              proof of causality.
            </li>
          )}
          {hasEvidence && (
            <li>
              <strong>Retinal evidence</strong> (lesion candidates / optic disc) is
              independent and advisory only: it never changes the AI grade or the
              referral decision.
            </li>
          )}
        </ul>
        <p className="note-text">
          Images are served by the backend from the screened case&apos;s own artifacts.
        </p>
      </div>
    </section>
  );
}