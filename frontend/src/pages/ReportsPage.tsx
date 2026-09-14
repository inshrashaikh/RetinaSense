/**
 * Reports — every screened case, each with a link to its screening report.
 * Reports are assembled by the backend from the real stored case data and are
 * never invented client-side.
 */
import { useMemo, useState } from 'react';
import { useCaseList } from '../hooks/useCaseList';
import { formatDate, statusLabel, statusTone } from '../utils/format';
import { Alert } from '../components/ui/Alert';
import { Badge } from '../components/ui/Badge';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { EmptyState } from '../components/ui/EmptyState';
import { SearchInput } from '../components/ui/Form';
import { PageHeader } from '../components/ui/PageHeader';
import { SkeletonRows } from '../components/ui/Skeleton';
import { StatusPill } from '../components/StatusPill';
import { navigate } from '../router';

export function ReportsPage() {
  const { state, cases, error, reload } = useCaseList();
  const [query, setQuery] = useState('');

  const screenable = useMemo(() => cases.filter((c) => c.status !== 'created'), [cases]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return screenable;
    return screenable.filter(
      (c) =>
        c.caseId.toLowerCase().includes(q) ||
        c.patientId.toLowerCase().includes(q) ||
        c.phcId.toLowerCase().includes(q),
    );
  }, [screenable, query]);

  return (
    <div className="page">
      <PageHeader
        eyebrow="Documentation"
        title="Reports"
        subtitle="Each screening case has a structured report assembled from the stored
          quality assessment, immutable AI result, human review, and final decision.
          A report is generated only from real backend data — never invented."
        actions={
          <Button icon="refresh" onClick={reload}>
            Refresh
          </Button>
        }
      />

      {error && <Alert variant="error" title={error.title}>{error.detail}</Alert>}

      <Card>
        <CardHeader
          title="Screening reports"
          subtitle="Cases that have completed at least the quality gate"
          icon="file"
          bordered
          actions={
            <Badge tone="brand" icon="file">
              {filtered.length} report{filtered.length === 1 ? '' : 's'}
            </Badge>
          }
        />

        {state === 'loading' && <SkeletonRows rows={4} />}

        {state === 'error' && (
          <CardBody>
            <Alert variant="error" title="Reports could not be listed">
              {error?.detail ?? 'Reports could not be listed while the backend is unreachable.'}
            </Alert>
            <div className="btn-row">
              <Button size="sm" icon="refresh" onClick={reload}>
                Try again
              </Button>
            </div>
          </CardBody>
        )}

        {state === 'done' && screenable.length === 0 && (
          <CardBody>
            <EmptyState
              icon="file"
              title="No reports yet"
              action={
                <Button variant="primary" icon="plus" onClick={() => navigate('/screening')}>
                  New screening
                </Button>
              }
            >
              Reports become available after a case has been screened. Cases awaiting
              only creation have nothing to report.
            </EmptyState>
          </CardBody>
        )}

        {state === 'done' && screenable.length > 0 && (
          <>
            <CardBody>
              <div className="toolbar">
                <SearchInput
                  label="Search reports"
                  placeholder="Search by case id, patient token or PHC…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
              </div>
            </CardBody>

            {filtered.length === 0 ? (
              <CardBody>
                <EmptyState icon="search" title="No reports match this search">
                  Clear the search to see every screened case.
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
                            <Button size="sm" onClick={() => navigate(`/reports/${c.caseId}`)}>
                              View report
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
