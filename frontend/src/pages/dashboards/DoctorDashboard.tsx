/**
 * DoctorDashboard — the ophthalmologist's clinical review view.
 *
 * The AI result is presented next to each pending case as a brief, but the
 * human always records the final decision. A brief that cannot be read is
 * shown as unavailable; nothing is inferred from a missing prediction.
 */
import { Alert } from '../../components/ui/Alert';
import { BackendHealthChip } from '../../components/BackendHealthChip';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Card, CardBody, CardHeader } from '../../components/ui/Card';
import { EmptyState } from '../../components/ui/EmptyState';
import { PageHeader } from '../../components/ui/PageHeader';
import { SkeletonRows, SkeletonStatGrid } from '../../components/ui/Skeleton';
import { StatCard } from '../../components/ui/StatCard';
import { RecentCasesTable } from '../../components/RecentCasesTable';
import { WorklistPanel } from '../../components/WorklistPanel';
import { useCaseBriefs, type CaseBrief } from '../../hooks/useCaseBriefs';
import { useCaseList, isAwaitingReview, isReviewed } from '../../hooks/useCaseList';
import { useStats } from '../../hooks/useStats';
import { formatDate, formatGradeLabel, formatPercent } from '../../utils/format';
import { navigate } from '../../router';

/** Cap the review worklist so the per-case brief lookups stay bounded. */
const REVIEW_WORKLIST_LIMIT = 8;

export function DoctorDashboard() {
  const { state: statsState, stats, reload: reloadStats } = useStats();
  const { state, cases, error, reload } = useCaseList();

  const pending = cases.filter(isAwaitingReview);
  const reviewed = cases.filter(isReviewed);
  const worklist = pending.slice(0, REVIEW_WORKLIST_LIMIT);
  const { briefs, failed, loading: briefsLoading } = useCaseBriefs(worklist.map((c) => c.caseId));

  return (
    <div className="page">
      <PageHeader
        eyebrow="Ophthalmologist console"
        title="Clinical review"
        subtitle="Review AI-assisted screenings and record the final referral decision.
          The AI result stays immutable; your decision is stored separately."
        actions={
          <>
            <Button variant="primary" icon="inbox" onClick={() => navigate('/review')}>
              Open review queue
            </Button>
          </>
        }
      />

      <Card aria-label="Clinical review statistics">
        <CardHeader
          title="Review workload"
          subtitle="Live counts from the backend case store"
          icon="gauge"
          actions={<BackendHealthChip />}
        />
        <CardBody>
          {statsState === 'loading' && <SkeletonStatGrid count={4} />}

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
                label="Pending reviews"
                value={stats.pendingReviews}
                icon="inbox"
                tone="info"
                note="Awaiting a human decision"
              />
              <StatCard
                label="Reviews recorded"
                value={stats.reviewed}
                icon="userCheck"
                tone="good"
                note="Human decision stored"
              />
              <StatCard
                label="Total cases"
                value={stats.totalCases}
                icon="layers"
                tone="brand"
                note="All cases on the backend"
              />
              <StatCard
                label="Recapture required"
                value={stats.recaptureRequired}
                icon="alert"
                tone="warn"
                note="Failed the quality gate"
              />
            </div>
          )}
        </CardBody>
      </Card>

      <Card aria-label="Pending clinical review">
        <CardHeader
          title="Pending clinical review"
          subtitle="Screened cases with an AI brief. The final decision is yours."
          icon="inbox"
          bordered
          actions={
            <Badge tone="info">
              {pending.length} case{pending.length === 1 ? '' : 's'}
            </Badge>
          }
        />

        {state === 'loading' && <SkeletonRows rows={4} />}

        {state === 'error' && (
          <CardBody>
            <Alert variant="error" title={error?.title ?? 'Cases unavailable'}>
              {error?.detail ??
                'The review worklist could not be loaded while the backend is unreachable.'}
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
            <EmptyState icon="checkCircle" title="Nothing awaiting review">
              Every screened case has a recorded human decision.
            </EmptyState>
          </CardBody>
        )}

        {state === 'done' && pending.length > 0 && (
          <CardBody className="card__body--flush-table">
            <div className="table-wrap">
              <table className="table table--compact table--stack">
                <thead>
                  <tr>
                    <th>Case</th>
                    <th>AI grading</th>
                    <th>Confidence</th>
                    <th>Uncertainty</th>
                    <th>Flags</th>
                    <th className="table__cell-actions" />
                  </tr>
                </thead>
                <tbody>
                  {worklist.map((c) => (
                    <tr key={c.caseId}>
                      <td data-label="Case" className="table__cell-strong">
                        {c.caseId}
                        <span className="table__cell-note">
                          {c.eye || 'Eye not recorded'} · {formatDate(c.createdAt)}
                        </span>
                      </td>
                      <td data-label="AI grading">
                        <AiBrief brief={briefs[c.caseId]} loading={briefsLoading} failed={failed.includes(c.caseId)} />
                      </td>
                      <td data-label="Confidence" className="muted">
                        {briefs[c.caseId] ? formatPercent(briefs[c.caseId].confidence) : '—'}
                      </td>
                      <td data-label="Uncertainty" className="muted">
                        {briefs[c.caseId] ? formatPercent(briefs[c.caseId].uncertainty) : '—'}
                      </td>
                      <td data-label="Flags">
                        <BriefFlags brief={briefs[c.caseId]} />
                      </td>
                      <td data-label="" className="table__cell-actions">
                        <Button
                          size="sm"
                          variant="primary"
                          aria-label={`Review — case ${c.caseId}`}
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
      </Card>

      <WorklistPanel
        label="Recently reviewed"
        description="Cases with a recorded human decision."
        icon="userCheck"
        badge="Reviewed"
        tone="good"
        cases={reviewed}
        state={state}
        actionLabel="Open case"
        onAction={(c) => navigate(`/case/${c.caseId}`)}
        emptyTitle="No reviews recorded yet"
        emptyBody="Cases appear here once you record a final decision."
      />

      <RecentCasesTable
        cases={cases}
        state={state}
        error={error}
        reload={reload}
        subtitle="Newest screenings recorded on the backend"
      />
    </div>
  );
}

function AiBrief({
  brief,
  loading,
  failed,
}: {
  brief: CaseBrief | undefined;
  loading: boolean;
  failed: boolean;
}) {
  if (failed) {
    return <span className="muted">AI brief unavailable</span>;
  }
  if (!brief) {
    return loading ? (
      <span className="muted">Reading AI result…</span>
    ) : (
      <span className="muted">AI result not loaded</span>
    );
  }
  if (brief.grade === null && brief.gradeLabel === null) {
    return <span className="muted">No AI result recorded</span>;
  }
  return (
    <span className="ai-brief">
      <strong>{formatGradeLabel(brief.grade, brief.gradeLabel)}</strong>
      {brief.referable === true && (
        <Badge tone="warn" icon="alert">
          Referable
        </Badge>
      )}
      {brief.referable === false && <Badge tone="good">Not referable</Badge>}
      {brief.referable === null && <Badge tone="neutral">Referability not recorded</Badge>}
    </span>
  );
}

function BriefFlags({ brief }: { brief: CaseBrief | undefined }) {
  if (!brief) return <span className="muted">—</span>;
  return (
    <span className="flag-row">
      {brief.reviewRequired === true && <Badge tone="info">Review flagged</Badge>}
      {brief.reviewRequired === false && <Badge tone="neutral">Not flagged</Badge>}
      {brief.gradCamAvailable && <Badge tone="brand" icon="spark">Grad-CAM</Badge>}
    </span>
  );
}
