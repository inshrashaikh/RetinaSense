/**
 * Final decision panel — the human-validated conclusion, shown separately from
 * the immutable AI prediction so the two can never be conflated.
 */
import type { AiPrediction, FinalDecision, HumanReview } from '../api/types';
import { formatGradeLabel } from '../utils/format';
import { hasPrediction } from '../api/types';
import { Badge } from './ui/Badge';
import { Card, CardBody, CardHeader, Row } from './ui/Card';
import { StatusPill } from './StatusPill';

interface Props {
  ai: AiPrediction | null;
  fd: FinalDecision | null;
  review: HumanReview | null;
}

export function FinalDecisionPanel({ ai, fd, review }: Props) {
  // No grade on the decision record means no referral determination exists yet
  // (e.g. a recapture-only review) — never present that as "non-referable".
  const hasFinalGrade = fd !== null && fd.grade !== null;

  return (
    <Card aria-label="Final decision" className="card--accent">
      <CardHeader
        title="Final decision"
        subtitle="Human-validated · stored separately from the AI result"
        icon="shieldCheck"
        bordered
        actions={<Badge tone="brand" icon="userCheck">Clinician decision</Badge>}
      />
      <CardBody>
        {!fd && !review ? (
          <p className="note-text">
            No final decision yet. The AI prediction alone is not a referral — a human
            review completes the decision.
          </p>
        ) : (
          <>
            {review && (
              <div className="rows">
                <Row label="Review action">
                  <StatusPill
                    tone={review.action === 'recapture' ? 'warn' : 'info'}
                    label={review.action}
                  />
                </Row>
                {review.reviewerId && <Row label="Reviewer">{review.reviewerId}</Row>}
                {review.notes && <Row label="Notes">{review.notes}</Row>}
              </div>
            )}

            <div className="rows">
              <Row label="Final DR grade" strong>
                {hasFinalGrade
                  ? `${fd.grade} · ${formatGradeLabel(fd.grade, fd.gradeLabel)}`
                  : (fd?.gradeLabel ?? 'Pending')}
              </Row>
              <Row label="Referral">
                {!hasFinalGrade ? (
                  <Badge tone="neutral" icon="hourglass">
                    Not determined
                  </Badge>
                ) : fd.referral ? (
                  <StatusPill tone="bad" label="Refer to ophthalmologist" />
                ) : (
                  <StatusPill tone="good" label="Non-referable" />
                )}
              </Row>
            </div>

            {!hasFinalGrade && (
              <p className="note-text">
                No final DR grade is recorded for this case yet, so no referral
                determination is shown. The AI result is not a referral on its own.
              </p>
            )}

            {hasPrediction(ai) && hasFinalGrade && ai.grade !== fd.grade && (
              <p className="note-text">
                The final grade (<strong>{fd.grade}</strong>) differs from the AI grade (<strong>{ai.grade}</strong>).{' '}
                The AI result is kept as-is; the approved decision above is the clinical
                conclusion.
              </p>
            )}
          </>
        )}
      </CardBody>
    </Card>
  );
}
