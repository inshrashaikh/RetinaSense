/**
 * OperatorDashboard — the PHC operator's screening operations view.
 *
 * An operator registers patients, captures fundus images and runs the quality
 * gate + AI grading. Final referral decisions belong to an ophthalmologist, so
 * this page surfaces capture work and hand-offs, never review controls.
 */
import { Alert } from '../../components/ui/Alert';
import { BackendHealthChip } from '../../components/BackendHealthChip';
import { Button } from '../../components/ui/Button';
import { Card, CardBody, CardHeader } from '../../components/ui/Card';
import { PageHeader } from '../../components/ui/PageHeader';
import { SkeletonStatGrid } from '../../components/ui/Skeleton';
import { StatCard } from '../../components/ui/StatCard';
import { RecentCasesTable } from '../../components/RecentCasesTable';
import { WorklistPanel } from '../../components/WorklistPanel';
import {
  useCaseList,
  isAwaitingScreening,
  isAwaitingReview,
  isRecaptureRequired,
} from '../../hooks/useCaseList';
import { useStats } from '../../hooks/useStats';
import { navigate } from '../../router';

export function OperatorDashboard() {
  const { state: statsState, stats, reload: reloadStats } = useStats();
  const { state, cases, error, reload } = useCaseList();

  const awaitingScreening = cases.filter(isAwaitingScreening);
  const recapture = cases.filter(isRecaptureRequired);
  const handedOff = cases.filter(isAwaitingReview);

  return (
    <div className="page">
      <PageHeader
        eyebrow="PHC operator console"
        title="Screening operations"
        subtitle="Capture fundus images, run the deterministic quality gate and AI grading,
          then hand screened cases to an ophthalmologist for the final referral decision."
        actions={
          <>
            <Button icon="layers" onClick={() => navigate('/cases')}>
              All cases
            </Button>
            <Button variant="primary" size="lg" icon="plus" onClick={() => navigate('/screening')}>
              New screening
            </Button>
          </>
        }
      />

      <Card aria-label="Operator queue statistics">
        <CardHeader
          title="Your queue"
          subtitle="Live counts from the backend case store"
          icon="gauge"
          actions={<BackendHealthChip />}
        />
        <CardBody>
          {statsState === 'loading' && <SkeletonStatGrid count={5} />}

          {statsState === 'unreachable' && (
            <Alert variant="info" title="Statistics unavailable">
              Statistics are unavailable while the backend is unreachable. Nothing is
              assumed in their place.
              <div className="btn-row">
                <Button size="sm" icon="refresh" onClick={reloadStats}>
                  Try again
                </Button>
              </div>
            </Alert>
          )}

          {statsState === 'done' && stats && (
            <div className="stat-grid">
              <StatCard
                label="Awaiting screening"
                value={stats.created}
                icon="hourglass"
                tone="brand"
                note="Registered, image not screened yet"
              />
              <StatCard
                label="Screenings completed"
                value={stats.screeningsCompleted}
                icon="checkCircle"
                tone="good"
                note="Quality gate + AI grading finished"
              />
              <StatCard
                label="Recapture required"
                value={stats.recaptureRequired}
                icon="alert"
                tone="warn"
                note="Failed the quality gate"
              />
              <StatCard
                label="Awaiting ophthalmologist"
                value={stats.pendingReviews}
                icon="inbox"
                tone="info"
                note="Handed off for the final decision"
              />
              <StatCard
                label="Total cases"
                value={stats.totalCases}
                icon="layers"
                tone="brand"
                note="All cases on the backend"
              />
            </div>
          )}
        </CardBody>
      </Card>

      <div className="grid-2">
        <WorklistPanel
          label="Awaiting screening"
          description="Registered cases that still need a fundus image."
          icon="hourglass"
          badge="Awaiting screening"
          tone="neutral"
          cases={awaitingScreening}
          state={state}
          actionLabel="Upload image"
          onAction={(c) => navigate(`/case/${c.caseId}/upload`)}
          emptyTitle="No captures outstanding"
          emptyBody="Every registered case already has an image through the quality gate."
        />

        <WorklistPanel
          label="Recapture required"
          description="Images that failed the quality gate and need a new capture."
          icon="alert"
          badge="Recapture required"
          tone="warn"
          cases={recapture}
          state={state}
          actionLabel="Re-capture"
          onAction={(c) => navigate(`/case/${c.caseId}/upload`)}
          emptyTitle="No recapture outstanding"
          emptyBody="No screened image is currently waiting to be taken again."
        />
      </div>

      <RecentCasesTable
        cases={cases}
        state={state}
        error={error}
        reload={reload}
        subtitle="Newest cases recorded at your screening point"
      />

      <Card aria-label="Hand-off to clinical review">
        <CardHeader
          title="Handed off for clinical review"
          subtitle="Screened cases waiting on an ophthalmologist"
          icon="inbox"
          actions={
            <Button size="sm" icon="arrowRight" onClick={() => navigate('/cases')}>
              Browse cases
            </Button>
          }
        />
        <CardBody>
          <Alert variant="info" title="Final decisions are made by an ophthalmologist">
            You can register, capture and screen cases, but you cannot approve or override an
            AI result. {handedOff.length === 1 ? '1 case is' : `${handedOff.length} cases are`} currently
            awaiting a clinical decision.
          </Alert>
        </CardBody>
      </Card>
    </div>
  );
}
