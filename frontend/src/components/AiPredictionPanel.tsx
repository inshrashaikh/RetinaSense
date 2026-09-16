/**
 * AI prediction panel. Displays the ORIGINAL AI result, which is immutable.
 * It is never overwritten by a human review.
 */
import type { AiPrediction } from '../api/types';
import { formatGradeLabel, formatPercent } from '../utils/format';
import { Badge } from './ui/Badge';
import { Card, CardBody, CardHeader, Row } from './ui/Card';
import { StatusPill } from './StatusPill';

const CLASS_NAMES = ['No DR', 'Mild NPDR', 'Moderate NPDR', 'Severe NPDR', 'Proliferative DR'];

function ProbabilityBar({ label, value }: { label: string; value: number }) {
  const pct = Math.round(value * 100);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
      <span style={{ width: 150, fontSize: 12, color: 'var(--muted-foreground, #6b7280)' }}>{label}</span>
      <div style={{ flex: 1, height: 10, background: 'rgba(127,127,127,0.15)', borderRadius: 999 }}>
        <div
          style={{
            width: `${pct}%`,
            height: '100%',
            borderRadius: 999,
            background: value >= 0.4 ? '#16a34a' : value >= 0.1 ? '#eab308' : '#3b82f6',
          }}
        />
      </div>
      <span style={{ width: 48, textAlign: 'right', fontSize: 12, fontVariantNumeric: 'tabular-nums' }}>
        {formatPercent(value)}
      </span>
    </div>
  );
}

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
        {ai.probabilities && ai.probabilities.length === 5 ? (
          <>
            <h4 style={{ margin: '14px 0 8px', fontSize: 13, color: 'var(--muted-foreground, #6b7280)' }}>
              Class probabilities
            </h4>
            {CLASS_NAMES.map((name, i) => {
              const v = ai.probabilities![i];
              return v === null || v === undefined ? null : <ProbabilityBar key={name} label={name} value={v} />;
            })}
          </>
        ) : null}
        <p className="note-text">
          This value is preserved verbatim for auditability and is never changed by human
          review. It is an assistive model output, not a diagnosis.
        </p>
      </CardBody>
    </Card>
  );
}
