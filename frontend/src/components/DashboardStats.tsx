/**
 * DashboardStats — backend-derived case metrics plus the screening workflow
 * overview. Counts come from GET /api/cases/stats; when the backend is
 * unreachable the cards say so instead of showing zeros.
 */
import { Fragment } from 'react';
import type { CaseStats } from '../api/types';
import { useStats } from '../hooks/useStats';
import { BackendHealthChip } from './BackendHealthChip';
import { Alert } from './ui/Alert';
import { Card, CardBody, CardHeader } from './ui/Card';
import { SkeletonStatGrid } from './ui/Skeleton';
import { StatCard, type StatTone } from './ui/StatCard';
import type { IconName } from './ui/Icon';
import { Icon } from './ui/Icon';

const METRICS: {
  key: keyof CaseStats;
  label: string;
  icon: IconName;
  tone: StatTone;
  note: string;
}[] = [
  { key: 'totalCases', label: 'Total cases', icon: 'layers', tone: 'brand', note: 'All cases on the backend' },
  { key: 'screeningsCompleted', label: 'Screenings completed', icon: 'checkCircle', tone: 'good', note: 'Quality gate + AI grading finished' },
  { key: 'pendingReviews', label: 'Pending reviews', icon: 'inbox', tone: 'info', note: 'Awaiting a human decision' },
  { key: 'reviewed', label: 'Reviewed', icon: 'userCheck', tone: 'good', note: 'Human decision recorded' },
  { key: 'recaptureRequired', label: 'Recapture required', icon: 'alert', tone: 'warn', note: 'Failed the quality gate' },
  { key: 'created', label: 'Awaiting screening', icon: 'hourglass', tone: 'brand', note: 'Created, not yet screened' },
];

const WORKFLOW_STEPS = ['Quality gate', 'AI grading', 'Human review'];

export function DashboardStats() {
  const { state, stats, health } = useStats();

  if (state === 'loading') {
    return (
      <Card aria-label="Overview statistics">
        <CardHeader title="Overview" subtitle="Reading live counts from the backend…" icon="gauge" />
        <CardBody>
          <SkeletonStatGrid count={6} />
        </CardBody>
      </Card>
    );
  }

  if (state === 'unreachable' || !stats) {
    return (
      <Card aria-label="Overview statistics">
        <CardHeader
          title="Overview"
          subtitle="Live counts from the backend case store"
          icon="gauge"
          actions={<BackendHealthChip />}
        />
        <CardBody>
          <Alert variant="info" title="Statistics unavailable">
            Statistics are unavailable while the backend is unreachable. Nothing is
            assumed in their place.
          </Alert>
        </CardBody>
      </Card>
    );
  }

  return (
    <div className="page-stack">
      <Card aria-label="Overview statistics">
        <CardHeader
          title="Overview"
          subtitle="Live counts from the backend case store"
          icon="gauge"
          actions={<BackendHealthChip />}
        />
        <CardBody>
          <div className="stat-grid">
            {METRICS.map((metric) => (
              <StatCard
                key={metric.key}
                label={metric.label}
                value={stats[metric.key]}
                note={metric.note}
                icon={metric.icon}
                tone={metric.tone}
              />
            ))}
          </div>
        </CardBody>
      </Card>

      <Card aria-label="Screening workflow">
        <CardHeader
          title="Screening workflow"
          subtitle="AI assists; the final referral decision is always human"
          icon="workflow"
        />
        <CardBody>
          <div className="pipeline-strip" role="note" aria-label="Screening workflow steps">
            {WORKFLOW_STEPS.map((step, i) => (
              <Fragment key={step}>
                <span className="pipeline-step">
                  <span className="pipeline-step__num" aria-hidden="true">
                    {i + 1}
                  </span>
                  {step}
                </span>
                <span className="pipeline-arrow" aria-hidden="true">
                  <Icon name="chevronRight" size={15} />
                </span>
              </Fragment>
            ))}
            <span className="pipeline-step pipeline-step--final">
              <span className="pipeline-step__num" aria-hidden="true">
                4
              </span>
              Final referral decision
            </span>
          </div>
          <p className="note-text">
            The AI result is never overwritten by a reviewer; the final decision is
            stored separately.
            {health && !health.matlabEngine
              ? ' The MATLAB AI engine is not connected, so real screening is currently unavailable.'
              : ''}
          </p>
        </CardBody>
      </Card>
    </div>
  );
}
