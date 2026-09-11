/**
 * Review queue — cases whose screening completed but no human decision was
 * recorded yet. The ophthalmologist reviews each case from its case page.
 */
import { useCallback, useEffect, useState } from 'react';
import { listCases } from '../api/endpoints';
import type { CaseListItem } from '../api/types';
import { ErrorBanner } from '../components/ErrorBanner';
import { StatusPill } from '../components/StatusPill';
import { navigate } from '../router';
import { friendlyError } from '../utils/errors';
import { statusTone, statusLabel } from '../utils/format';
import { formatDate } from './CasesPage';

type ListState = 'loading' | 'done' | 'error';

export function ReviewQueuePage() {
  const [state, setState] = useState<ListState>('loading');
  const [pending, setPending] = useState<CaseListItem[]>([]);
  const [reviewedCount, setReviewedCount] = useState(0);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);

  const load = useCallback(async () => {
    setState('loading');
    setError(null);
    try {
      const items = await listCases();
      setPending(items.filter((c) => c.status === 'completed'));
      setReviewedCount(items.filter((c) => c.status === 'reviewed').length);
      setState('done');
    } catch (err) {
      setError(friendlyError(err));
      setState('error');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="page">
      <h1>Human review</h1>
      <p className="page-intro">
        Cases below have an AI result and are waiting for an ophthalmologist's
        decision (approve / override / recapture). The AI result is immutable — the
        review is recorded separately as the final decision.
      </p>

      {error && <ErrorBanner title={error.title} detail={error.detail} />}

      {state === 'done' && reviewedCount > 0 && (
        <p className="note-text">{reviewedCount} case(s) already reviewed.</p>
      )}

      {state === 'done' && pending.length === 0 && (
        <section className="panel">
          <h2 className="panel-title">Nothing to review</h2>
          <p className="empty-note">
            No completed screening is waiting for a human decision. Cases appear here
            after the quality gate and AI grading finish.
          </p>
        </section>
      )}

      {state === 'done' && pending.length > 0 && (
        <section className="panel" aria-label="Review queue">
          <table className="case-table">
            <thead>
              <tr>
                <th>Case</th>
                <th>Status</th>
                <th>Eye</th>
                <th>Created</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {pending.map((c) => (
                <tr key={c.caseId}>
                  <td>{c.caseId}</td>
                  <td>
                    <StatusPill tone={statusTone(c.status)} label={statusLabel(c.status)} />
                  </td>
                  <td className="muted">{c.eye || '—'}</td>
                  <td className="muted">{formatDate(c.createdAt)}</td>
                  <td>
                    <button type="button" className="btn btn-primary btn-sm" onClick={() => navigate(`/case/${c.caseId}`)}>
                      Review
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {state === 'error' && (
        <section className="panel">
          <p className="empty-note">
            The review queue could not be loaded while the backend is unreachable.
          </p>
          <button type="button" className="btn" onClick={() => void load()}>
            Try again
          </button>
        </section>
      )}
    </div>
  );
}