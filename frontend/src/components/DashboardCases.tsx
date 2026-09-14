/**
 * DashboardCases — the operational view of the case store: recent cases plus
 * the two worklists that need action (awaiting review, recapture required).
 *
 * One backend read (GET /api/cases) feeds all three panels.
 */
import type { CaseListItem } from '../api/types';
import { navigate } from '../router';
import { useCaseList, isAwaitingReview, isRecaptureRequired } from '../hooks/useCaseList';
import { formatDate, statusLabel, statusTone } from '../utils/format';
import { Alert } from './ui/Alert';
import { Badge } from './ui/Badge';
import { Button } from './ui/Button';
import { Card, CardBody, CardHeader } from './ui/Card';
import { EmptyState } from './ui/EmptyState';
import { SkeletonRows } from './ui/Skeleton';
import { StatusPill } from './StatusPill';

const RECENT_LIMIT = 8;

export function DashboardCases() {
  const { state, cases, error, reload } = useCaseList();

  const recent = cases.slice(0, RECENT_LIMIT);
  const awaitingReview = cases.filter(isAwaitingReview);
  const recapture = cases.filter(isRecaptureRequired);

  return (
    <>
      <Card aria-label="Recent cases">
        <CardHeader
          title="Recent cases"
          subtitle="Newest screenings recorded on the backend"
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
            <div className="btn-row">
              <Button size="sm" icon="refresh" onClick={reload}>
                Try again
              </Button>
            </div>
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

      <div className="grid-2">
        <WorklistPanel
          label="Awaiting review"
          description="Screened cases with an AI result and no human decision yet."
          icon="inbox"
          badge="Awaiting review"
          tone="info"
          cases={awaitingReview}
          state={state}
          actionLabel="Review"
          onAction={(c) => navigate(`/case/${c.caseId}`)}
          emptyTitle="Nothing awaiting review"
          emptyBody="Every screened case has a recorded human decision."
        />

        <WorklistPanel
          label="Recapture required"
          description="Images that failed the quality gate and need a new capture."
          icon="alert"
          badge="Recapture required"
          tone="warn"
          cases={recapture}
          state={state}
          actionLabel="Open case"
          onAction={(c) => navigate(`/case/${c.caseId}`)}
          emptyTitle="No recapture outstanding"
          emptyBody="No screened image is currently waiting to be taken again."
        />
      </div>
    </>
  );
}

interface WorklistProps {
  label: string;
  description: string;
  icon: 'inbox' | 'alert';
  badge: string;
  tone: 'info' | 'warn';
  cases: CaseListItem[];
  state: 'loading' | 'done' | 'error';
  actionLabel: string;
  onAction: (c: CaseListItem) => void;
  emptyTitle: string;
  emptyBody: string;
}

function WorklistPanel({
  label,
  description,
  icon,
  badge,
  tone,
  cases,
  state,
  actionLabel,
  onAction,
  emptyTitle,
  emptyBody,
}: WorklistProps) {
  return (
    <Card aria-label={label}>
      <CardHeader
        title={label}
        subtitle={description}
        icon={icon}
        bordered
        actions={<Badge tone={tone}>{cases.length} case{cases.length === 1 ? '' : 's'}</Badge>}
      />

      {state === 'loading' && <SkeletonRows rows={2} />}

      {state === 'error' && (
        <CardBody>
          <p className="note-text">
            This worklist could not be loaded while the backend is unreachable.
          </p>
        </CardBody>
      )}

      {state === 'done' && cases.length === 0 && (
        <CardBody>
          <EmptyState icon={icon} title={emptyTitle}>
            {emptyBody}
          </EmptyState>
        </CardBody>
      )}

      {state === 'done' && cases.length > 0 && (
        <CardBody className="card__body--flush-list">
          <ul className="data-list">
            {cases.slice(0, 5).map((c) => (
              <li className="data-list__item" key={c.caseId}>
                {/* The case id is exposed through the action's accessible name
                    rather than duplicated in the visible list. */}
                <span className="data-list__main">
                  <span className="data-list__title">
                    {c.patientId ? `Patient ${c.patientId}` : 'Patient token not recorded'}
                  </span>
                  <span className="data-list__meta">
                    <Badge tone={tone} icon={tone === 'warn' ? 'alert' : 'inbox'}>
                      {badge}
                    </Badge>
                    <span>{c.eye || 'Eye not recorded'}</span>
                    <span>{formatDate(c.createdAt)}</span>
                  </span>
                </span>
                <Button
                  size="sm"
                  aria-label={`${actionLabel} — case ${c.caseId}`}
                  onClick={() => onAction(c)}
                >
                  {actionLabel}
                </Button>
              </li>
            ))}
          </ul>
        </CardBody>
      )}
    </Card>
  );
}
