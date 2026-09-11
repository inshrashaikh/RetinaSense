/**
 * AI prediction panel. Displays the ORIGINAL AI result, which is immutable.
 * It is never overwritten by a human review.
 */
import type { AiPrediction } from '../api/types';
import { formatGradeLabel, formatPercent } from '../utils/format';
import { StatusPill } from './StatusPill';

export function AiPredictionPanel({ ai }: { ai: AiPrediction | null }) {
  if (!ai) {
    return (
      <section className="panel" aria-label="AI prediction">
        <h2 className="panel-title">AI prediction</h2>
        <p className="empty-note">No AI prediction was produced for this image
          (for example, the image was ungradable or the screening engine was
          unavailable). Nothing is shown in place of a real result.</p>
      </section>
    );
  }

  return (
    <section className="panel" aria-label="AI prediction">
      <h2 className="panel-title">AI prediction (original, immutable)</h2>
      <div className="panel-row">
        <span className="panel-label">DR grade</span>
        <span className="panel-value panel-value-strong">
          {ai.grade === null ? '—' : ai.grade} · {formatGradeLabel(ai.grade, ai.gradeLabel)}
        </span>
      </div>
      <div className="panel-row">
        <span className="panel-label">Referable (Level 2+)</span>
        {ai.referable === null ? (
          <span className="panel-value">—</span>
        ) : ai.referable ? (
          <StatusPill tone="bad" label="Referable" />
        ) : (
          <StatusPill tone="good" label="Non-referable" />
        )}
      </div>
      <div className="panel-row">
        <span className="panel-label">Confidence</span>
        <span className="panel-value">{formatPercent(ai.confidence)}</span>
      </div>
      <div className="panel-row">
        <span className="panel-label">Uncertainty</span>
        <span className="panel-value">{formatPercent(ai.uncertainty)}</span>
      </div>
      <div className="panel-row">
        <span className="panel-label">Review required</span>
        {ai.reviewRequired ? (
          <StatusPill tone="warn" label="Required" />
        ) : (
          <span className="panel-value">Not required</span>
        )}
      </div>
      <p className="note-text">This value is preserved verbatim for auditability and is never changed by human review.</p>
    </section>
  );
}