/**
 * Quality gate result panel — the deterministic assessment that runs before any
 * grading, including the recapture instruction when an image is rejected.
 */
import type { QualityResult } from '../api/types';
import { formatScore, qualityClassLabel } from '../utils/format';
import { Alert } from './ui/Alert';
import { Card, CardBody, CardHeader, Row } from './ui/Card';
import { StatusPill } from './StatusPill';
import type { StatusTone } from '../utils/format';

function toneFor(cls: string | null | undefined): StatusTone {
  switch ((cls ?? '').toLowerCase()) {
    case 'good':
      return 'good';
    case 'borderline':
      return 'warn';
    case 'ungradable':
      return 'bad';
    default:
      return 'neutral';
  }
}

export function QualityPanel({ quality }: { quality: QualityResult }) {
  const cls = quality.class ?? null;
  const score = quality.score;
  const hasScore = score !== null && score !== undefined && !Number.isNaN(score);

  return (
    <Card aria-label="Image quality result">
      <CardHeader
        title="Image quality"
        subtitle="Deterministic gate · runs before any grading"
        icon="gauge"
        bordered
      />
      <CardBody>
        <div className="rows">
          <Row label="Quality class">
            <StatusPill tone={toneFor(cls)} label={qualityClassLabel(cls)} />
          </Row>
          <Row label="Quality score">{formatScore(score)}</Row>
        </div>

        {hasScore && (
          <div className="meter" aria-hidden="true">
            <span className="meter__fill" style={{ width: `${Math.round(score! * 100)}%` }} />
          </div>
        )}

        {quality.failureReasons.length > 0 && (
          <div className="block">
            <p className="block__title">Why this image was not “good”</p>
            <ul className="reason-list">
              {quality.failureReasons.map((r) => (
                <li key={r}>{r}</li>
              ))}
            </ul>
          </div>
        )}

        {(quality.recaptureReason || quality.recaptureInstruction) && (
          <Alert variant="warning" title="Recapture requested" icon="camera">
            {quality.recaptureReason && (
              <p>
                <span className="row__label">Reason:</span>{' '}
                <span className="mono">{quality.recaptureReason}</span>
              </p>
            )}
            {quality.recaptureInstruction && (
              <p>
                <span className="row__label">How to retake:</span> {quality.recaptureInstruction}
              </p>
            )}
          </Alert>
        )}
      </CardBody>
    </Card>
  );
}
