/**
 * AdminDashboard — system-level monitoring for an administrator.
 *
 * Only what the backend actually exposes is shown: engine/database health and
 * aggregate case counts. User management, audit logs and Simulink capacity are
 * not provided by the current API, so an honest note says so rather than
 * rendering empty controls.
 */
import { Alert } from '../../components/ui/Alert';
import { BackendHealthChip } from '../../components/BackendHealthChip';
import { Button } from '../../components/ui/Button';
import { Card, CardBody, CardHeader, Row } from '../../components/ui/Card';
import { PageHeader } from '../../components/ui/PageHeader';
import { SkeletonStatGrid } from '../../components/ui/Skeleton';
import { StatCard } from '../../components/ui/StatCard';
import { RecentCasesTable } from '../../components/RecentCasesTable';
import { useCaseList } from '../../hooks/useCaseList';
import { useStats } from '../../hooks/useStats';
import { navigate } from '../../router';

export function AdminDashboard() {
  const { state, stats, health, reload } = useStats();
  const { state: listState, cases, error, reload: reloadCases } = useCaseList();

  return (
    <div className="page">
      <PageHeader
        eyebrow="Administrator console"
        title="System administration"
        subtitle="Monitor the screening service and the backend case store. This is a
          prototype: administrative data comes only from endpoints the API exposes."
        actions={
          <Button icon="layers" onClick={() => navigate('/cases')}>
            Browse all cases
          </Button>
        }
      />

      <div className="grid-2">
        <Card aria-label="Backend system health">
          <CardHeader
            title="System health"
            subtitle="Live status from GET /api/health"
            icon="activity"
            actions={<BackendHealthChip />}
          />
          <CardBody>
            {state === 'loading' && <SkeletonStatGrid count={1} />}

            {state === 'unreachable' && (
              <Alert variant="warning" title="Backend unreachable">
                The backend did not answer the health check. No status is reported until it
                responds again.
              </Alert>
            )}

            {state === 'done' && health && (
              <div className="rows">
                <Row label="Backend status" strong>
                  {health.status}
                </Row>
                <Row label="MATLAB AI engine">
                  {health.matlabEngine ? 'Connected' : 'Not connected'}
                </Row>
                <Row label="Case database">{health.database ?? 'Not reported'}</Row>
                <Row label="Service version">{health.version}</Row>
              </div>
            )}

            <div className="btn-row">
              <Button size="sm" icon="refresh" onClick={reload}>
                Refresh
              </Button>
            </div>
          </CardBody>
        </Card>

        <Card aria-label="Operational backlog">
          <CardHeader
            title="Operational backlog"
            subtitle="Counts the service is currently holding"
            icon="gauge"
          />
          <CardBody>
            {state === 'loading' && <SkeletonStatGrid count={3} />}
            {state === 'unreachable' && (
              <p className="note-text">
                Backlog counts are unavailable while the backend is unreachable.
              </p>
            )}
            {state === 'done' && stats && (
              <div className="rows">
                <Row label="Pending reviews" strong>
                  {stats.pendingReviews}
                </Row>
                <Row label="Recapture required" strong>
                  {stats.recaptureRequired}
                </Row>
                <Row label="Awaiting screening" strong>
                  {stats.created}
                </Row>
              </div>
            )}
            <p className="note-text">
              Backlog items are counted from the case store; no throughput or capacity target is
              assumed.
            </p>
          </CardBody>
        </Card>
      </div>

      <Card aria-label="Case-store overview">
        <CardHeader
          title="Case-store overview"
          subtitle="Live counts from the backend case store"
          icon="layers"
        />
        <CardBody>
          {state === 'loading' && <SkeletonStatGrid count={6} />}

          {state === 'unreachable' && (
            <Alert variant="info" title="Statistics unavailable">
              Statistics are unavailable while the backend is unreachable. Nothing is
              assumed in their place.
            </Alert>
          )}

          {state === 'done' && stats && (
            <div className="stat-grid">
              <StatCard label="Total cases" value={stats.totalCases} icon="layers" tone="brand" />
              <StatCard
                label="Screenings completed"
                value={stats.screeningsCompleted}
                icon="checkCircle"
                tone="good"
              />
              <StatCard label="Pending reviews" value={stats.pendingReviews} icon="inbox" tone="info" />
              <StatCard label="Reviewed" value={stats.reviewed} icon="userCheck" tone="good" />
              <StatCard
                label="Recapture required"
                value={stats.recaptureRequired}
                icon="alert"
                tone="warn"
              />
              <StatCard label="Awaiting screening" value={stats.created} icon="hourglass" tone="brand" />
            </div>
          )}
        </CardBody>
      </Card>

      <Alert variant="info" title="Administrative controls not exposed by the API">
        The current backend does not provide user/role management, audit-log or
        MATLAB/Simulink capacity endpoints. No account list or capacity figure is shown in
        their place.
      </Alert>

      <RecentCasesTable
        cases={cases}
        state={listState}
        error={error}
        reload={reloadCases}
        subtitle="Newest entries in the case store"
      />
    </div>
  );
}
