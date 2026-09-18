/**
 * SimulationDashboard — district-scale capacity view for the admin role.
 *
 * Shows the measured district telemedicine workflow (A → acquisition →
 * network → AI → review → completed) driven by the real SimEvents capacity
 * model (simulink/DRTelemedicine.slx). The %numbers% come ONLY from
 * GET /api/simulation/capacity, which serves the measured output JSON of a
 * real simulation run; when no run exists the page reports that honestly and
 * never substitutes a figure. The 100,000/yr target is shown as a reference,
 * clearly separated from measured throughput.
 */
import { Alert } from '../../components/ui/Alert';
import { BackendHealthChip } from '../../components/BackendHealthChip';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Card, CardBody, CardHeader, Row } from '../../components/ui/Card';
import { Icon } from '../../components/ui/Icon';
import { EmptyState } from '../../components/ui/EmptyState';
import { PageHeader } from '../../components/ui/PageHeader';
import { SkeletonStatGrid, SkeletonValue } from '../../components/ui/Skeleton';
import { StatCard } from '../../components/ui/StatCard';
import { useSimulationCapacity } from '../../hooks/useSimulationCapacity';
import { useCaseList, isAwaitingReview, isRecaptureRequired, isAwaitingScreening } from '../../hooks/useCaseList';
import { useStats } from '../../hooks/useStats';
import { formatPercent } from '../../utils/format';
import { isMeasured } from '../../api/types';
import { navigate } from '../../router';
import { Fragment } from 'react';

const WORKFLOW_STEPS = [
  'Patient arrival',
  'Acquisition (camera)',
  'Transmission (network)',
  'AI grading',
  'Ophthalmologist review',
];

/** Resources of the district model (matches simulink Run scenario output). */
const RESOURCE_UTILS: Array<{
  label: string;
  field: 'acqUtilization' | 'networkUtilization' | 'aiUtilization' | 'revUtilization';
  icon: 'camera' | 'eye' | 'spark' | 'users' | 'activity';
}> = [
  { label: 'Acquisition', field: 'acqUtilization', icon: 'camera' },
  { label: 'Network / transmission', field: 'networkUtilization', icon: 'eye' },
  { label: 'AI processing', field: 'aiUtilization', icon: 'spark' },
  { label: 'Ophthalmologist review', field: 'revUtilization', icon: 'users' },
];

const SCENARIO_LABELS: Record<string, string> = {
  baseline: 'Baseline (district load)',
  low_load: 'Low load',
  high_load: 'High load',
  rural_1mbps: 'Rural 1 Mbps',
  rural_4mbps: 'Rural 4 Mbps',
  solo_reviewer: 'Single reviewer',
  team_5_reviewers: '5 reviewers',
};

function scenarioLabel(name: string): string {
  return SCENARIO_LABELS[name] ?? name;
}

function fmt(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—';
  return value.toLocaleString(undefined, {
    maximumFractionDigits: digits,
    minimumFractionDigits: digits,
  });
}

export function SimulationDashboard() {
  const { state, data, error, reload } = useSimulationCapacity();
  const { state: statsState, stats, health, reload: reloadStats } = useStats();
  const { state: listState, cases } = useCaseList();

  const latest = data?.latest ?? null;
  const measured = (latest?.results ?? []).filter(isMeasured);
  const baseline = measured.find((r) => r.scenario === 'baseline');
  const hasResults = data?.available === true && measured.length > 0;

  return (
    <div className="page">
      <PageHeader
        eyebrow="District operations · simulation"
        title="Capacity & district operations"
        subtitle="Measured district-scale telemedicine capacity from the SimEvents model.
          Every figure below is read from a real simulation run — nothing is assumed."
        actions={
          <>
            <Button icon="layers" onClick={() => navigate('/cases')}>
              Browse cases
            </Button>
            <Button variant="ghost" size="sm" icon="refresh" onClick={reload}>
              Refresh
            </Button>
          </>
        }
      />

      <Card aria-label="District workflow">
        <CardHeader
          title="District telemedicine workflow"
          subtitle="The discrete-event model chain (simulink/DRTelemedicine.slx)"
          icon="workflow"
        />
        <CardBody>
          <div className="pipeline-strip" role="note" aria-label="District workflow steps">
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
                {WORKFLOW_STEPS.length + 1}
              </span>
              Completed screening
            </span>
          </div>
          <p className="note-text">
            Referrals (8%) flow through the review stage; recaptures (10%) return to the
            acquisition stage. Throughput is reported only for a full simulated workday.
          </p>
        </CardBody>
      </Card>

      {state === 'loading' && <SkeletonStatGrid count={5} />}

      {state === 'unreachable' && (
        <Alert variant="info" title="Capacity results unavailable">
          {error?.detail ?? 'The simulation results could not be loaded.'}
          <div className="btn-row">
            <Button size="sm" icon="refresh" onClick={reload}>
              Try again
            </Button>
          </div>
        </Alert>
      )}

      {state === 'done' && !hasResults && (
        <Card aria-label="Capacity results">
          <CardHeader
            title="Measured capacity"
            subtitle="GET /api/simulation/capacity"
            icon="gauge"
            actions={<BackendHealthChip />}
          />
          <CardBody>
            <EmptyState icon="hourglass" title="No measured simulation results yet">
              <p>
                The capacity model needs a MATLAB R2026a + SimEvents run
                (<code>run_simulink_scenarios</code>) to produce
                <code>simulink/output/district_capacity_results_*.json</code>.
                Until a run exists, no throughput or capacity figure is shown.
              </p>
            </EmptyState>
          </CardBody>
        </Card>
      )}

      {hasResults && baseline && (
        <Card aria-label="Measured baseline capacity">
          <CardHeader
            title="Measured baseline capacity"
            subtitle="MEASURED from SimEvents block statistics — never extrapolated"
            icon="gauge"
            actions={
              <>
                <Badge tone="brand">
                  Bottleneck: {baseline.bottleneck ?? 'not identified'}
                </Badge>
                <BackendHealthChip />
              </>
            }
          />
          <CardBody>
            <div className="stat-grid">
              <StatCard
                label="Throughput"
                value={`${fmt(baseline.throughput)}/day`}
                icon="activity"
                tone="brand"
                note="Completed screenings per full workday"
              />
              <StatCard
                label="Annual capacity (measured)"
                value={fmt(baseline.annualCapacity)}
                icon="calendar"
                tone="info"
                note="Based on the measured workday throughput"
              />
              <StatCard
                label="Avg acquisition wait"
                value={`${fmt(baseline.averageWaitingTime)} s`}
                icon="hourglass"
                tone="warn"
                note="MEASURED queue wait (Acquisition)"
              />
              <StatCard
                label="Avg queue length"
                value={fmt(baseline.queueLength, 1)}
                icon="layers"
                tone="info"
                note="MEASURED Acquisition queue"
              />
              <StatCard
                label="Reviewer utilization"
                value={formatPercent(baseline.reviewerUtilization)}
                icon="userCheck"
                tone="good"
                note="MEASURED Review server utilization"
              />
            </div>
          </CardBody>
        </Card>
      )}

      {data?.target && (
        <Alert
          variant="warning"
          title={`100,000 patients/year is a reference target, not a result`}
          icon="target"
        >
          The measurement above is the model's actual throughput. The
          {data.target.dailyEquivalent.toLocaleString()} patients/day target from
          the problem statement is shown for comparison only — the current single
          acquisition station does not reach it. {data.target.note}
        </Alert>
      )}

      {hasResults && (
        <Card aria-label="Scenario comparison">
          <CardHeader
            title="Scenario comparison"
            subtitle="What-if runs measured by the model (all MEASURED throughput)"
            icon="sliders"
            actions={<Badge tone="neutral">{measured.length} run{measured.length === 1 ? '' : 's'}</Badge>}
          />
          <CardBody className="card__body--flush-table">
            <div className="table-wrap">
              <table className="table table--compact table--stack">
                <thead>
                  <tr>
                    <th>Scenario</th>
                    <th>Load / day</th>
                    <th>Throughput</th>
                    <th>Annual capacity</th>
                    <th>Avg wait</th>
                    <th>Queue</th>
                    <th>Bottleneck</th>
                  </tr>
                </thead>
                <tbody>
                  {measured.map((r) => (
                    <tr key={r.scenario}>
                      <td data-label="Scenario" className="table__cell-strong">
                        {scenarioLabel(r.scenario)}
                      </td>
                      <td data-label="Load / day">{fmt(r.patientsPerDay)}</td>
                      <td data-label="Throughput">
                        {r.throughput === null ? '—' : `${fmt(r.throughput)}/day`}
                      </td>
                      <td data-label="Annual capacity">{fmt(r.annualCapacity)}</td>
                      <td data-label="Avg wait">
                        {r.averageWaitingTime === null ? '—' : `${fmt(r.averageWaitingTime)} s`}
                      </td>
                      <td data-label="Queue">{fmt(r.queueLength, 1)}</td>
                      <td data-label="Bottleneck" className="muted">
                        {r.bottleneck ?? '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </CardBody>
        </Card>
      )}

      {hasResults && baseline && (
        <div className="grid-2">
          <Card aria-label="Resource utilization">
            <CardHeader
              title="Resource utilization"
              subtitle="Analytical M/M/1 estimates from the same scenario parameters"
              icon="activity"
            />
            <CardBody>
              {state === 'done' && (
                <div className="rows">
                  {RESOURCE_UTILS.map((res) => {
                    const value = baseline[res.field];
                    return (
                      <Row key={res.field} label={res.label}>
                        {value === null || value === undefined || Number.isNaN(value) ? (
                          <span className="muted">—</span>
                        ) : (
                          <span className="util-row">
                            <span className="util-bar" aria-hidden="true">
                              <span
                                className="util-bar__fill"
                                style={{ width: `${Math.min(value * 100, 100)}%` }}
                              />
                            </span>
                            {formatPercent(value)}
                          </span>
                        )}
                      </Row>
                    );
                  })}
                </div>
              )}
            </CardBody>
          </Card>

          <Card aria-label="Live service state">
            <CardHeader
              title="Live service state"
              subtitle="Current backend status"
              icon="activity"
              actions={<BackendHealthChip />}
            />
            <CardBody>
              {statsState === 'loading' && <SkeletonValue label="Reading status…" />}
              {statsState === 'done' && health && (
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
              {statsState === 'unreachable' && (
                <p className="note-text">
                  Status is unavailable while the backend is unreachable.
                </p>
              )}
              <div className="btn-row">
                <Button size="sm" icon="refresh" onClick={reloadStats}>
                  Refresh
                </Button>
              </div>
            </CardBody>
          </Card>
        </div>
      )}

      <Card aria-label="Operational case counts">
        <CardHeader
          title="Operational case counts"
          subtitle="Live counts from the backend case store"
          icon="layers"
        />
        <CardBody>
          {listState === 'loading' && <SkeletonStatGrid count={4} />}
          {listState === 'done' && (
            <div className="stat-grid">
              <StatCard
                label="Awaiting screening"
                value={cases.filter(isAwaitingScreening).length}
                icon="hourglass"
                tone="brand"
              />
              <StatCard
                label="Pending review"
                value={cases.filter(isAwaitingReview).length}
                icon="inbox"
                tone="info"
              />
              <StatCard
                label="Recapture required"
                value={cases.filter(isRecaptureRequired).length}
                icon="alert"
                tone="warn"
              />
              <StatCard
                label="Total on backend"
                value={stats?.totalCases ?? 0}
                icon="layers"
                tone="brand"
              />
            </div>
          )}
        </CardBody>
      </Card>

      {latest && latest.dataSourcePolicy && (
        <p className="note-text">
          <Icon name="info" size={13} /> {latest.dataSourcePolicy}
        </p>
      )}
    </div>
  );
}