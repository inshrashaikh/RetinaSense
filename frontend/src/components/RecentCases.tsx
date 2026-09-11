/**
 * Recent cases — fetched from the persistent backend store (GET /api/cases).
 * Shows the newest few cases in a compact table, plus a link to the full list.
 */
import { useEffect, useState } from 'react';
import { listCases } from '../api/endpoints';
import type { CaseListItem } from '../api/types';
import { navigate } from '../router';
import { StatusPill } from './StatusPill';
import { statusTone, statusLabel } from '../utils/format';
import { formatDate } from '../pages/CasesPage';

type ListState = 'loading' | 'done' | 'error';

export function RecentCases() {
  const [state, setState] = useState<ListState>('loading');
  const [cases, setCases] = useState<CaseListItem[]>([]);

  useEffect(() => {
    let cancelled = false;
    listCases()
      .then((items) => {
        if (cancelled) return;
        setCases(items);
        setState('done');
      })
      .catch(() => {
        if (cancelled) return;
        setState('error');
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <section className="panel" aria-label="Recent cases">
      <div className="panel-head-row">
        <h2 className="panel-title">Recent cases</h2>
        <button type="button" className="link-btn" onClick={() => navigate('/cases')}>
          View all cases
        </button>
      </div>

      {state === 'loading' && <p className="empty-note">Loading recent cases…</p>}

      {state === 'error' && (
        <p className="empty-note">
          Recent cases could not be loaded. No case list is assumed while the
          backend is unreachable.
        </p>
      )}

      {state === 'done' && cases.length === 0 && (
        <p className="empty-note">
          No screening has been run yet. Recent cases are read from the persistent
          backend store.
        </p>
      )}

      {state === 'done' && cases.length > 0 && (
        <table className="case-table case-table-compact">
          <thead>
            <tr>
              <th>Case</th>
              <th>Status</th>
              <th>Eye</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            {cases.slice(0, 8).map((c) => (
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
                <td className="muted">{formatDate(c.createdAt)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </section>
  );
}