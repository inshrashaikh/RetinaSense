/**
 * Review queue — cases whose screening completed but no human decision has been
 * recorded yet. The ophthalmologist reviews each case from its case page.
 */
import { useMemo, useState } from 'react';
import { useCaseList, isAwaitingReview } from '../hooks/useCaseList';
import { formatDate, statusLabel, statusTone } from '../utils/format';
import { Alert } from '../components/ui/Alert';
import { Badge } from '../components/ui/Badge';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { EmptyState } from '../components/ui/EmptyState';
import { SearchInput } from '../components/ui/Form';
import { PageHeader } from '../components/ui/PageHeader';
import { SkeletonRows } from '../components/ui/Skeleton';
import { StatCard } from '../components/ui/StatCard';
import { StatusPill } from '../components/StatusPill';
import { navigate } from '../router';

export function ReviewQueuePage() {
  const { state, cases, error, reload } = useCaseList();
  const [query, setQuery] = useState('');

  const pending = useMemo(() => cases.filter(isAwaitingReview), [cases]);
  const reviewedCount = useMemo(
    () => cases.filter((c) => c.status === 'reviewed').length,
    [cases],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return pending;
    return pending.filter(
      (c) =>
        c.caseId.toLowerCase().includes(q) ||
        c.patientId.toLowerCase().includes(q) ||
        c.phcId.toLowerCase().includes(q),
    );
  }, [pending, query]);

  return (
    <div className="page">
      <PageHeader
        eyebrow="Human in the loop"
        title="Review queue"
        subtitle="Cases below have an AI result and are waiting for an ophthalmologist's
          decision (approve / override / recapture). The AI result is immutable — the
          review is recorded separately as the final decision."
        actions={
          <Button icon="refresh" onClick={reload}>
            Refresh queue
          </Button>
        }
      />

      {error && <Alert variant="error" title={error.title}>{error.detail}</Alert>}

      <div className="grid-2">
        <StatCard
          label="Awaiting review"
          value={state === 'done' ? pending.length : '—'}
          note="Screened cases without a decision"
          icon="inbox"
          tone="info"
        />
        <StatCard
          label="Review completed"
          value={state === 'done' ? reviewedCount : '—'}
          note="Cases with a recorded human decision"
          icon="userCheck"
          tone="good"
        />
      </div>

      <Card>
        <CardHeader
          title="Waiting for a decision"
          subtitle="Oldest reviewed first when processing the list top-down"
          icon="clipboard"
          bordered
          actions={<Badge tone="info" icon="clock">{filtered.length} pending</Badge>}
        />

        {state === 'loading' && <SkeletonRows rows={4} />}

        {state === 'error' && (
          <CardBody>
            <Alert variant="error" title="Review queue unavailable">
              {error?.detail ??
                'The review queue could not be loaded while the backend is unreachable.'}
            </Alert>
            <div className="btn-row">
              <Button size="sm" icon="refresh" onClick={reload}>
                Try again
              </Button>
            </div>
          </CardBody>
        )}

        {state === 'done' && pending.length === 0 && (
          <CardBody>
            <EmptyState
              icon="checkCircle"
              title="Nothing to review"
              action={
                <Button icon="layers" onClick={() => navigate('/cases')}>
                  Browse all cases
                </Button>
              }
            >
              No completed screening is waiting for a human decision. Cases appear here
              after the quality gate and AI grading finish.
            </EmptyState>
          </CardBody>
        )}

        {state === 'done' && pending.length > 0 && (
          <>
            <CardBody>
              <div className="toolbar">
                <SearchInput
                  label="Search review queue"
                  placeholder="Search by case id, patient token or PHC…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
              </div>
            </CardBody>

            {filtered.length === 0 ? (
              <CardBody>
                <EmptyState icon="search" title="No pending cases match this search">
                  Clear the search to see every case waiting for a decision.
                </EmptyState>
              </CardBody>
            ) : (
              <CardBody className="card__body--flush">
                <div className="table-wrap">
                  <table className="table table--stack">
                    <thead>
                      <tr>
                        <th>Case</th>
                        <th>Status</th>
                        <th>Eye</th>
                        <th>Created</th>
                        <th className="table__cell-actions">
                          <span className="sr-only">Actions</span>
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {filtered.map((c) => (
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
                            <Button
                              variant="primary"
                              size="sm"
                              onClick={() => navigate(`/case/${c.caseId}`)}
                            >
                              Review
                            </Button>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardBody>
            )}
          </>
        )}
      </Card>
    </div>
  );
}
