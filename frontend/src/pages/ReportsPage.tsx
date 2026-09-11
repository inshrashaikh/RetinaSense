/**
 * Reports page — every case that has been screened, each with a link to its
 * screening report. Reports are assembled by the backend from the real stored
 * case data (POST /api/cases/{caseId}/report) and retrieved from the backend.
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

export function ReportsPage() {
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

  const screenable = cases.filter((c) => c.status !== 'created');

  return (
    <div className="page">
      <h1>Reports</h1>
      <p className="page-intro">
        Each screening case has a structured report assembled from the stored
        quality assessment, immutable AI result, human review, and final decision.
        A report is generated only from real backend data — never invented.
      </p>

      {error && <ErrorBanner title={error.title} detail={error.detail} />}

      {state === 'done' && screenable.length === 0 && (
        <section className="panel">
          <h2 className="panel-title">No reports yet</h2>
          <p className="empty-note">
            Reports become available after a case has been screened. Cases awaiting
            only creation have nothing to report.
          </p>
          <div className="btn-row">
            <button type="button" className="btn btn-primary" onClick={() => navigate('/screening')}>
              New screening
            </button>
          </div>
        </section>
      )}

      {state === 'done' && screenable.length > 0 && (
        <section className="panel" aria-label="Report list">
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
              {screenable.map((c) => (
                <tr key={c.caseId}>
                  <td>{c.caseId}</td>
                  <td>
                    <StatusPill tone={statusTone(c.status)} label={statusLabel(c.status)} />
                  </td>
                  <td className="muted">{c.eye || '—'}</td>
                  <td className="muted">{formatDate(c.createdAt)}</td>
                  <td>
                    <button type="button" className="btn btn-sm" onClick={() => navigate(`/reports/${c.caseId}`)}>
                      View report
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
            Reports could not be listed while the backend is unreachable.
          </p>
          <button type="button" className="btn" onClick={() => void load()}>
            Try again
          </button>
        </section>
      )}
    </div>
  );
}