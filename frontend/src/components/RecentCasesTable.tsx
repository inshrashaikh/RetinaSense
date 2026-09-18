/**
 * RecentCasesTable — the newest cases recorded on the backend.
 *
 * Shared by the role dashboards and the generic console. It never invents a
 * case: an empty or unreachable backend is shown as such.
 */
import type { CaseListItem } from '../api/types';
import { navigate } from '../router';
import { formatDate, statusLabel, statusTone } from '../utils/format';
import type { FriendlyError } from '../utils/errors';
import { Alert } from './ui/Alert';
import { Button } from './ui/Button';
import { Card, CardBody, CardHeader } from './ui/Card';
import { EmptyState } from './ui/EmptyState';
import { SkeletonRows } from './ui/Skeleton';
import { StatusPill } from './StatusPill';

export interface RecentCasesTableProps {
  cases: CaseListItem[];
  state: 'loading' | 'done' | 'error';
  error?: FriendlyError | null;
  reload?: () => void;
  limit?: number;
  subtitle?: string;
}

export function RecentCasesTable({
  cases,
  state,
  error,
  reload,
  limit = 8,
  subtitle = 'Newest screenings recorded on the backend',
}: RecentCasesTableProps) {
  const recent = cases.slice(0, limit);

  return (
    <Card aria-label="Recent cases">
      <CardHeader
        title="Recent cases"
        subtitle={subtitle}
        icon="layers"
        bordered
        actions={
          <Button size="sm" icon="arrowRight" onClick={() => navigate('/cases')}>
            View all cases
          </Button>
        }
      />

      {state === 'loading' && <SkeletonRows rows={4} />}

      {state === 'error' && (
        <CardBody>
          <Alert variant="error" title={error?.title ?? 'Cases unavailable'}>
            {error?.detail ??
              'Recent cases could not be loaded. No case list is assumed while the backend is unreachable.'}
          </Alert>
          {reload && (
            <div className="btn-row">
              <Button size="sm" icon="refresh" onClick={reload}>
                Try again
              </Button>
            </div>
          )}
        </CardBody>
      )}

      {state === 'done' && cases.length === 0 && (
        <CardBody>
          <EmptyState
            icon="layers"
            title="No screening has been run yet"
            action={
              <Button variant="primary" icon="plus" onClick={() => navigate('/screening')}>
                Start the first screening
              </Button>
            }
          >
            Cases appear here as soon as a fundus image goes through the quality gate
            and AI grading.
          </EmptyState>
        </CardBody>
      )}

      {state === 'done' && cases.length > 0 && (
        <CardBody className="card__body--flush-table">
          <div className="table-wrap">
            <table className="table table--compact table--stack">
              <thead>
                <tr>
                  <th>Case</th>
                  <th>Status</th>
                  <th>Eye</th>
                  <th>Created</th>
                  <th className="table__cell-actions" />
                </tr>
              </thead>
              <tbody>
                {recent.map((c) => (
                  <tr key={c.caseId}>
                    <td data-label="Case" className="table__cell-strong">
                      {c.caseId}
                    </td>
                    <td data-label="Status">
                      <StatusPill tone={statusTone(c.status)} label={statusLabel(c.status)} />
                    </td>
                    <td data-label="Eye" className="muted">
                      {c.eye || '—'}
                    </td>
                    <td data-label="Created" className="muted">
                      {formatDate(c.createdAt)}
                    </td>
                    <td data-label="" className="table__cell-actions">
                      <Button size="sm" onClick={() => navigate(`/case/${c.caseId}`)}>
                        Open
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </CardBody>
      )}
    </Card>
  );
}
