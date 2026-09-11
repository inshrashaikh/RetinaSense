/**
 * Final decision panel — the human-validated conclusion, shown separately from
 * the immutable AI prediction so the two can never be conflated.
 */
import type { AiPrediction, FinalDecision, HumanReview } from '../api/types';
import { formatGradeLabel } from '../utils/format';
import { StatusPill } from './StatusPill';

interface Props {
  ai: AiPrediction | null;
  fd: FinalDecision | null;
  review: HumanReview | null;
}

export function FinalDecisionPanel({ ai, fd, review }: Props) {
  return (
    <section className="panel panel-final" aria-label="Final decision">
      <h2 className="panel-title">Final decision</h2>

      {!fd && !review ? (
        <p className="empty-note">No final decision yet. The AI prediction alone is
          not a referral — a human review completes the decision.</p>
      ) : (
        <>
          {review && (
            <div className="panel-row">
              <span className="panel-label">Review action</span>
              <StatusPill
                tone={review.action === 'recapture' ? 'warn' : 'info'}
                label={review.action}
              />
            </div>
          )}
          <div className="panel-row">
            <span className="panel-label">Final DR grade</span>
            <span className="panel-value panel-value-strong">
              {fd && fd.grade !== null
                ? `${fd.grade} · ${formatGradeLabel(fd.grade, fd.gradeLabel)}`
                : 'Pending recapture'}
            </span>
          </div>
          <div className="panel-row">
            <span className="panel-label">Referral</span>
            {fd?.referral === null || fd?.referral === undefined ? (
              <span className="panel-value">—</span>
            ) : fd.referral ? (
              <StatusPill tone="bad" label="Refer to ophthalmologist" />
            ) : (
              <StatusPill tone="good" label="Non-referable" />
            )}
          </div>

          {ai && fd && fd.grade !== null && ai.grade !== null && fd.grade !== ai.grade && (
            <p className="note-text">
              The final grade (<strong>{fd.grade}</strong>) differs from the AI grade (<strong>{ai.grade}</strong>).
              The AI result is kept as-is; the approved decision above is the clinical conclusion.
            </p>
          )}
        </>
      )}
    </section>
  );
}