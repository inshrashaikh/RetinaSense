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

type Action = 'approve' | 'override' | 'recapture';

interface Props {
  caseId: string;
  ai: AiPrediction | null;
  onSubmitted: (r: ReviewResponse) => void;
  onError: (title: string, detail: string) => void;
}

export function ReviewPanel({ caseId, ai, onSubmitted, onError }: Props) {
  const [action, setAction] = useState<Action>('approve');
  const [overrideGrade, setOverrideGrade] = useState<number>(2);
  const [reviewerId, setReviewerId] = useState('');
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);

  if (!ai || ai.grade === null) {
    return (
      <section className="panel" aria-label="Human review">
        <h2 className="panel-title">Human review</h2>
        <p className="empty-note">
          No AI grade exists for this image, so a review is not applicable.
          {ai && ai.reviewRequired ? ' Review is recorded as required at the backend.' : ''}
        </p>
      </section>
    );
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!reviewerId.trim()) {
      onError('Reviewer ID required', 'Please enter the reviewer (ophthalmologist) ID before submitting.');
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
    <section className="panel" aria-label="Human review">
      <h2 className="panel-title">Human review</h2>

      <p className="note-text">
        AI grade is <strong>{ai.grade} ({ai.gradeLabel})</strong>. The AI result is
        preserved verbatim; your decision below is recorded separately as the final decision.
      </p>

      <form onSubmit={onSubmit}>
        <fieldset className="fieldset">
          <legend>Action</legend>
          <label className="radio-line">
            <input type="radio" name="action" value="approve" checked={action === 'approve'}
              onChange={() => setAction('approve')} />
            Approve AI result
          </label>
          <label className="radio-line">
            <input type="radio" name="action" value="override" checked={action === 'override'}
              onChange={() => setAction('override')} />
            Override grade
          </label>
          <label className="radio-line">
            <input type="radio" name="action" value="recapture" checked={action === 'recapture'}
              onChange={() => setAction('recapture')} />
            Request recapture
          </label>
        </fieldset>

        {action === 'override' && (
          <label className="field">
            <span className="field-label">Override DR grade</span>
            <select
              value={overrideGrade}
              onChange={(e) => setOverrideGrade(Number(e.target.value))}
              aria-label="Override DR grade"
            >
              {[0, 1, 2, 3, 4].map((g) => (
                <option key={g} value={g}>
                  {g}
                </option>
              ))}
            </select>
          </label>
        )}

        <label className="field">
          <span className="field-label">Reviewer (ophthalmologist) ID</span>
          <input
            type="text"
            value={reviewerId}
            onChange={(e) => setReviewerId(e.target.value)}
            placeholder="e.g. OPH-2"
            autoComplete="off"
          />
        </label>

        <label className="field">
          <span className="field-label">Notes</span>
          <textarea
            rows={3}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Optional notes…"
          />
        </label>

        <button type="submit" className="btn btn-primary" disabled={busy}>
          {busy ? 'Submitting review…' : 'Submit review'}
        </button>
      </form>
    </section>
  );
}