/**
 * AI prediction panel. Displays the ORIGINAL AI result, which is immutable.
 * It is never overwritten by a human review.
 */
import type { AiPrediction } from '../api/types';
import { formatGradeLabel, formatPercent } from '../utils/format';
import { Badge } from './ui/Badge';
import { Card, CardBody, CardHeader, Row } from './ui/Card';
import { StatusPill } from './StatusPill';

export function AiPredictionPanel({ ai }: { ai: AiPrediction | null }) {
  // A non-null object with a null grade means the backend did not produce a
  // prediction (never screened / grading not reached) — never render it as one.
  if (!ai || ai.grade === null) {
    return (
      <Card aria-label="AI prediction">
        <CardHeader
          title="AI prediction"
          subtitle="Not produced for this image"
          icon="spark"
          bordered
          actions={<Badge tone="neutral">No result</Badge>}
        />
        <CardBody>
          <p className="note-text">
            No AI prediction was produced for this image (for example, the image was
            ungradable or the screening engine was unavailable). Nothing is shown in
            place of a real result.
          </p>
        </CardBody>
      </Card>
    );
  }

  return (
    <Card aria-label="AI prediction">
      <CardHeader
        title="AI prediction"
        subtitle="Original result · immutable"
        icon="spark"
        bordered
        actions={<Badge tone="brand" icon="lock">Preserved verbatim</Badge>}
      />
      <CardBody>
        <div className="rows">
          <Row label="DR grade" strong>
            {ai.grade === null ? '—' : ai.grade} · {formatGradeLabel(ai.grade, ai.gradeLabel)}
          </Row>
          <Row label="Referable (Level 2+)">
            {ai.referable === null ? (
              '—'
            ) : ai.referable ? (
              <StatusPill tone="bad" label="Referable" />
            ) : (
              <StatusPill tone="good" label="Non-referable" />
            )}
          </Row>
          <Row label="Confidence">{formatPercent(ai.confidence)}</Row>
          <Row label="Uncertainty">{formatPercent(ai.uncertainty)}</Row>
          <Row label="Review required">
            {ai.reviewRequired ? (
              <StatusPill tone="warn" label="Required" />
            ) : (
              <span>Not required</span>
            )}
          </Row>
        </div>
        <p className="note-text">
          This value is preserved verbatim for auditability and is never changed by human
          review. It is an assistive model output, not a diagnosis.
        </p>
      </CardBody>
    </Card>
  );
}
