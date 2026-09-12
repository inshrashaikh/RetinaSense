/**
 * Human review panel (ophthalmologist):
 * approve / override / recapture + reviewer id + notes.
 *
 * The AI prediction is never modified here — the review is submitted as a
 * separate payload and the final decision is derived from the review.
 */
import { useState } from 'react';
import type { AiPrediction, ReviewResponse } from '../api/types';
import { submitReview } from '../api/endpoints';
import { friendlyError } from '../utils/errors';
import { Button } from './ui/Button';
import { Card, CardBody, CardHeader } from './ui/Card';
import { Field, Input, Select, Textarea } from './ui/Form';
import { Badge } from './ui/Badge';
import { Alert } from './ui/Alert';

type Action = 'approve' | 'override' | 'recapture';

interface Props {
  caseId: string;
  ai: AiPrediction | null;
  onSubmitted: (r: ReviewResponse) => void;
  onError: (title: string, detail: string) => void;
}

const ACTIONS: { value: Action; label: string; hint: string }[] = [
  { value: 'approve', label: 'Approve grade', hint: 'Accept the AI grade as the final grade.' },
  { value: 'override', label: 'Override grade', hint: 'Record a different final DR grade.' },
  { value: 'recapture', label: 'Request recapture', hint: 'No reliable grade — take a new image.' },
];

export function ReviewPanel({ caseId, ai, onSubmitted, onError }: Props) {
  const [action, setAction] = useState<Action>('approve');
  const [overrideGrade, setOverrideGrade] = useState<number>(2);
  const [reviewerId, setReviewerId] = useState('');
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [reviewerError, setReviewerError] = useState('');

  if (!ai || ai.grade === null) {
    return (
      <Card aria-label="Human review">
        <CardHeader
          title="Human review"
          subtitle="Not applicable for this case"
          icon="userCheck"
          bordered
        />
        <CardBody>
          <p className="note-text">
            No AI grade exists for this image, so a review is not applicable.
            {ai && ai.reviewRequired ? ' Review is recorded as required at the backend.' : ''}
          </p>
        </CardBody>
      </Card>
    );
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setReviewerError('');
    if (!reviewerId.trim()) {
      setReviewerError('Enter the reviewer (ophthalmologist) ID before submitting.');
      return;
    }
    setBusy(true);
    try {
      const res = await submitReview(caseId, {
        action,
        reviewerId: reviewerId.trim(),
        overrideGrade: action === 'override' ? overrideGrade : null,
        notes,
      });
      onSubmitted(res);
    } catch (err) {
      const f = friendlyError(err);
      onError(f.title, f.detail);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card aria-label="Human review">
      <CardHeader
        title="Human review"
        subtitle="Recorded separately from the AI result"
        icon="userCheck"
        bordered
        actions={
          <Badge tone="info" icon="spark">
            AI grade {ai.grade} ({ai.gradeLabel})
          </Badge>
        }
      />
      <CardBody>
        <Alert variant="info" title="How this is recorded" role="note">
          The AI result is preserved verbatim; your decision below is stored separately as
          the final decision for this case.
        </Alert>

        <form className="form" onSubmit={onSubmit} aria-label="Human review form">
          <fieldset className="fieldset">
            <legend className="fieldset__legend">Action</legend>
            {ACTIONS.map((option) => (
              <label className="radio-line" key={option.value}>
                <input
                  type="radio"
                  name="action"
                  value={option.value}
                  aria-label={option.label}
                  checked={action === option.value}
                  onChange={() => setAction(option.value)}
                />
                <span className="radio-line__text">
                  <span>{option.label}</span>
                  <span className="radio-line__hint">{option.hint}</span>
                </span>
              </label>
            ))}
          </fieldset>

          {action === 'override' && (
            <Field label="Override DR grade">
              <Select
                value={overrideGrade}
                onChange={(e) => setOverrideGrade(Number(e.target.value))}
              >
                {[0, 1, 2, 3, 4].map((g) => (
                  <option key={g} value={g}>
                    {g}
                  </option>
                ))}
              </Select>
            </Field>
          )}

          <Field
            label="Reviewer (ophthalmologist) ID"
            error={reviewerError || undefined}
          >
            <Input
              type="text"
              value={reviewerId}
              onChange={(e) => setReviewerId(e.target.value)}
              placeholder="e.g. OPH-2"
              autoComplete="off"
            />
          </Field>

          <Field label="Notes">
            <Textarea
              rows={3}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder="Optional notes…"
            />
          </Field>

          <div className="btn-row">
            <Button type="submit" variant="primary" icon="check" loading={busy}>
              {busy ? 'Submitting review…' : 'Submit review'}
            </Button>
          </div>
        </form>
      </CardBody>
    </Card>
  );
}
