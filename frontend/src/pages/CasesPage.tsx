/**
 * Cases page — full list of all cases from the backend, newest first.
 * Every value comes from GET /api/cases (single source of truth: backend DB).
 */
import { useCallback, useEffect, useMemo, useState } from 'react';
import { listCases } from '../api/endpoints';
import type { CaseListItem } from '../api/types';
import { ErrorBanner } from '../components/ErrorBanner';
import { StatusPill } from '../components/StatusPill';
import { navigate } from '../router';
import { friendlyError } from '../utils/errors';
import { statusTone, statusLabel } from '../utils/format';

type ListState = 'loading' | 'done' | 'error';
type CaseFilter = 'all' | 'referable' | 'pending' | 'recapture';

const FILTER_LABELS: Record<CaseFilter, string> = {
  all: 'All',
  referable: 'Referable',
  pending: 'Pending review',
  recapture: 'Recapture needed',
};

export function CasesPage() {
  const [state, setState] = useState<ListState>('loading');
  const [cases, setCases] = useState<CaseListItem[]>([]);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);
  const [filter, setFilter] = useState<CaseFilter>('all');

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

  const filtered = useMemo<CaseListItem[]>(() => {
    if (filter === 'all') return cases;
    if (filter === 'referable') return cases.filter((c) => c.referable === true);
    if (filter === 'pending') return cases.filter((c) => c.status === 'completed');
    return cases.filter((c) => c.status === 'recapture_required');
  }, [cases, filter]);

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

      {state === 'done' && (
        <div className="filter-tabs" role="tablist" aria-label="Filter cases">
          {(Object.keys(FILTER_LABELS) as CaseFilter[]).map((f) => (
            <button
              key={f}
              type="button"
              role="tab"
              aria-selected={filter === f}
              className={`filter-tab${filter === f ? ' filter-tab-active' : ''}`}
              onClick={() => setFilter(f)}
            >
              {FILTER_LABELS[f]}
            </button>
          ))}
        </div>
      )}

      {state === 'done' && filtered.length === 0 && (
        <section className="panel">
          <h2 className="panel-title">No cases yet</h2>
          <p className="empty-note">
            {filter === 'all'
              ? 'No screenings have been run. Create the first case with “New screening”.'
              : `No cases match the “${FILTER_LABELS[filter]}” filter.`}
          </p>
        </section>
      )}

      {state === 'done' && filtered.length > 0 && (
        <section className="panel" aria-label="Case list">
          <table className="case-table">
            <thead>
              <tr>
                <th>Case</th>
                <th>Status</th>
                <th>Eye</th>
                <th>PHC</th>
                <th>Referable</th>
                <th>Created</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {filtered.map((c) => (
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
                  <td className="muted">
                    {c.referable === null || c.referable === undefined ? (
                      '—'
                    ) : c.referable ? (
                      <StatusPill tone="bad" label="Referable" />
                    ) : (
                      <StatusPill tone="good" label="Non-referable" />
                    )}
                  </td>
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