/**
 * Quality gate result panel.
 */
import type { QualityResult } from '../api/types';
import { formatScore, qualityClassLabel } from '../utils/format';
import { StatusPill } from './StatusPill';

function toneFor(cls: string | null | undefined) {
  switch ((cls ?? '').toLowerCase()) {
    case 'good':
      return 'good' as const;
    case 'borderline':
      return 'warn' as const;
    case 'ungradable':
      return 'bad' as const;
    default:
      return 'neutral' as const;
  }
}

export function QualityPanel({ quality }: { quality: QualityResult }) {
  const cls = quality.class ?? null;
  const label = qualityClassLabel(cls);

  return (
    <section className="panel" aria-label="Image quality result">
      <h2 className="panel-title">Image quality</h2>
      <div className="panel-row">
        <span className="panel-label">Quality class</span>
        <StatusPill tone={toneFor(cls)} label={label} />
      </div>
      <div className="panel-row">
        <span className="panel-label">Quality score</span>
        <span className="panel-value">{formatScore(quality.score)}</span>
      </div>

      {quality.failureReasons.length > 0 && (
        <div className="panel-block">
          <h3 className="panel-subheading">Why this image was not “good”</h3>
          <ul className="reason-list">
            {quality.failureReasons.map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        </div>
      )}

      {(quality.recaptureReason || quality.recaptureInstruction) && (
        <div className="recapture-box" role="note">
          <h3 className="panel-subheading">Recapture requested</h3>
          {quality.recaptureReason && (
            <p>
              <span className="panel-label">Reason:</span> {quality.recaptureReason}
            </p>
          )}
          {quality.recaptureInstruction && (
            <p>
              <span className="panel-label">How to retake:</span> {quality.recaptureInstruction}
            </p>
          )}
        </div>
      )}
    </section>
  );
}