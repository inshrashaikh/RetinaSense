/**
 * WorklistPanel — a case list that needs human action (e.g. awaiting review,
 * recapture, awaiting screening). Shared by the role dashboards and the
 * generic console so every worklist reads and behaves the same way.
 */
import type { CaseListItem } from '../api/types';
import { formatDate } from '../utils/format';
import { Badge } from './ui/Badge';
import { Button } from './ui/Button';
import { Card, CardBody, CardHeader } from './ui/Card';
import { EmptyState } from './ui/EmptyState';
import { SkeletonRows } from './ui/Skeleton';
import type { IconName } from './ui/Icon';
import type { StatusTone } from '../utils/format';

export interface WorklistPanelProps {
  label: string;
  description: string;
  icon: IconName;
  badge: string;
  tone: StatusTone;
  cases: CaseListItem[];
  state: 'loading' | 'done' | 'error';
  actionLabel: string;
  onAction: (c: CaseListItem) => void;
  emptyTitle: string;
  emptyBody: string;
  /** How many rows to show before the list is considered long. */
  limit?: number;
}

export function WorklistPanel({
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
  limit = 5,
}: WorklistPanelProps) {
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
            {cases.slice(0, limit).map((c) => (
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
