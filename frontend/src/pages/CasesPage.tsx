/**
 * Cases page — full list of all cases from the backend, newest first.
 * Every value comes from GET /api/cases (single source of truth: backend DB).
 */
import { useCallback, useEffect, useState } from 'react';
import { listCases } from '../api/endpoints';
import type { CaseListItem } from '../api/types';
import { ErrorBanner } from '../components/ErrorBanner';
import { StatusPill } from '../components/StatusPill';
import { navigate } from '../router';
import { friendlyError } from '../utils/errors';
import { statusTone, statusLabel } from '../utils/format';

type ListState = 'loading' | 'done' | 'error';

export function CasesPage() {
  const [state, setState] = useState<ListState>('loading');
  const [cases, setCases] = useState<CaseListItem[]>([]);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);

  const load = useCallback(async () => {
    setState('loading');
    setError(null);
    try {
      const items = await listCases();
      setCases(items);
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
      <div className="page-head-row">
        <div>
          <h1>Cases</h1>
          <p className="page-intro">
            Every screening case stored on the backend. Open a case to see its
            result, complete the human review, or generate its report.
          </p>
        </div>
        <button type="button" className="btn btn-primary" onClick={() => navigate('/screening')}>
          New screening
        </button>
      </div>

      {error && <ErrorBanner title={error.title} detail={error.detail} />}

      {state === 'done' && cases.length === 0 && (
        <section className="panel">
          <h2 className="panel-title">No cases yet</h2>
          <p className="empty-note">
            No screenings have been run. Create the first case with “New screening”.
          </p>
        </section>
      )}

      {state === 'done' && cases.length > 0 && (
        <section className="panel" aria-label="Case list">
          <table className="case-table">
            <thead>
              <tr>
                <th>Case</th>
                <th>Status</th>
                <th>Eye</th>
                <th>PHC</th>
                <th>Created</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {cases.map((c) => (
                <tr key={c.caseId}>
                  <td>
                    <button type="button" className="link-btn" onClick={() => navigate(`/case/${c.caseId}`)}>
                      {c.caseId}
                    </button>
                  </td>
                  <td>
                    <StatusPill tone={statusTone(c.status)} label={statusLabel(c.status)} />
                  </td>
                  <td className="muted">{c.eye || '—'}</td>
                  <td className="muted">{c.phcId || '—'}</td>
                  <td className="muted">{c.createdAt ? formatDate(c.createdAt) : '—'}</td>
                  <td>
                    <button type="button" className="btn btn-sm" onClick={() => navigate(`/case/${c.caseId}`)}>
                      Open
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
            Cases could not be loaded. No list is assumed while the backend is unreachable.
          </p>
          <button type="button" className="btn" onClick={() => void load()}>
            Try again
          </button>
        </section>
      )}
    </div>
  );
}

export function formatDate(iso: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}