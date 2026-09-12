/**
 * Cases — the full case list, searchable and filterable.
 * Every value comes from GET /api/cases (single source of truth: backend DB).
 */
import { useMemo, useState } from 'react';
import { useCaseList } from '../hooks/useCaseList';
import { formatDate, statusLabel, statusTone } from '../utils/format';
import { Alert } from '../components/ui/Alert';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { EmptyState } from '../components/ui/EmptyState';
import { SearchInput, Select } from '../components/ui/Form';
import { PageHeader } from '../components/ui/PageHeader';
import { SkeletonRows } from '../components/ui/Skeleton';
import { StatusPill } from '../components/StatusPill';
import { navigate } from '../router';

/**
 * Filter labels deliberately differ from the status badge wording so a row
 * status is never confused with a filter option.
 */
const STATUS_FILTERS = [
  { value: '', label: 'All statuses' },
  { value: 'created', label: 'Awaiting screening' },
  { value: 'completed', label: 'Awaiting review' },
  { value: 'reviewed', label: 'Review completed' },
  { value: 'recapture_required', label: 'Needs recapture' },
];

export function CasesPage() {
  const { state, cases, error, reload } = useCaseList();
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('');

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return cases.filter((c) => {
      if (status && c.status !== status) return false;
      if (!q) return true;
      return (
        c.caseId.toLowerCase().includes(q) ||
        c.patientId.toLowerCase().includes(q) ||
        c.phcId.toLowerCase().includes(q)
      );
    });
  }, [cases, query, status]);

  return (
    <div className="page">
      <PageHeader
        eyebrow="Case management"
        title="Cases"
        subtitle="Every screening case stored on the backend. Open a case to see its
          result, complete the human review, or generate its report."
        actions={
          <>
            <Button icon="clipboard" onClick={() => navigate('/cases/new')}>
              Create case
            </Button>
            <Button variant="primary" icon="plus" onClick={() => navigate('/screening')}>
              New screening
            </Button>
          </>
        }
      />

      {error && <Alert variant="error" title={error.title}>{error.detail}</Alert>}

      <Card>
        <CardHeader
          title="All cases"
          subtitle={
            state === 'done'
              ? `${filtered.length} of ${cases.length} case${cases.length === 1 ? '' : 's'} shown`
              : 'Loading the case list from the backend'
          }
          icon="layers"
          bordered
          actions={
            <Button size="sm" icon="refresh" onClick={reload}>
              Refresh
            </Button>
          }
        />

        {state === 'loading' && <SkeletonRows rows={5} />}

        {state === 'error' && (
          <CardBody>
            <Alert variant="error" title="Cases could not be loaded">
              {error?.detail ??
                'Cases could not be loaded. No list is assumed while the backend is unreachable.'}
            </Alert>
            <div className="btn-row">
              <Button size="sm" icon="refresh" onClick={reload}>
                Try again
              </Button>
            </div>
          </CardBody>
        )}

        {state === 'done' && (
          <>
            <CardBody>
              <div className="toolbar">
                <SearchInput
                  label="Search cases"
                  placeholder="Search by case id, patient token or PHC…"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                />
                <Select
                  aria-label="Filter by status"
                  value={status}
                  onChange={(e) => setStatus(e.target.value)}
                >
                  {STATUS_FILTERS.map((f) => (
                    <option key={f.value} value={f.value}>
                      {f.label}
                    </option>
                  ))}
                </Select>
                {(query || status) && (
                  <Button
                    size="sm"
                    variant="ghost"
                    icon="x"
                    onClick={() => {
                      setQuery('');
                      setStatus('');
                    }}
                  >
                    Clear filters
                  </Button>
                )}
              </div>
            </CardBody>

            {cases.length === 0 && (
              <CardBody>
                <EmptyState
                  icon="layers"
                  title="No cases yet"
                  action={
                    <Button variant="primary" icon="plus" onClick={() => navigate('/screening')}>
                      New screening
                    </Button>
                  }
                >
                  No screenings have been run. Create the first case with “New
                  screening”, or register a case first and upload the image afterwards.
                </EmptyState>
              </CardBody>
            )}

            {cases.length > 0 && filtered.length === 0 && (
              <CardBody>
                <EmptyState icon="search" title="No cases match these filters">
                  Try a different search term or reset the status filter.
                </EmptyState>
              </CardBody>
            )}

            {filtered.length > 0 && (
              <CardBody className="card__body--flush">
                <div className="table-wrap">
                  <table className="table table--stack">
                    <thead>
                      <tr>
                        <th>Case</th>
                        <th>Status</th>
                        <th>Eye</th>
                        <th>PHC</th>
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
                            <button
                              type="button"
                              className="link-btn"
                              onClick={() => navigate(`/case/${c.caseId}`)}
                            >
                              {c.caseId}
                            </button>
                          </td>
                          <td data-label="Status">
                            <StatusPill tone={statusTone(c.status)} label={statusLabel(c.status)} />
                          </td>
                          <td data-label="Eye" className="muted">
                            {c.eye || '—'}
                          </td>
                          <td data-label="PHC" className="muted">
                            {c.phcId || '—'}
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
          </>
        )}
      </Card>
    </div>
  );
}
