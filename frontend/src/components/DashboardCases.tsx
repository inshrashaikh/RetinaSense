/**
 * DashboardCases — the operational view of the case store for the generic
 * console: recent cases plus the two worklists that need action (awaiting
 * review, recapture required).
 *
 * One backend read (GET /api/cases) feeds all three panels.
 */
import { navigate } from '../router';
import { useCaseList, isAwaitingReview, isRecaptureRequired } from '../hooks/useCaseList';
import { RecentCasesTable } from './RecentCasesTable';
import { WorklistPanel } from './WorklistPanel';

export function DashboardCases() {
  const { state, cases, error, reload } = useCaseList();

  const awaitingReview = cases.filter(isAwaitingReview);
  const recapture = cases.filter(isRecaptureRequired);

  return (
    <>
      <RecentCasesTable cases={cases} state={state} error={error} reload={reload} />

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
