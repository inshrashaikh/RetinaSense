/**
 * Screening result — opens the most recent case from the backend. With no
 * cases yet, shows an honest empty state. With cases, renders the case page
 * (quality gate → AI result → review → final decision).
 */
import { useCaseList } from '../hooks/useCaseList';
import { Alert } from '../components/ui/Alert';
import { Button } from '../components/ui/Button';
import { EmptyState } from '../components/ui/EmptyState';
import { PageHeader } from '../components/ui/PageHeader';
import { LoadingBlock } from '../components/ui/Skeleton';
import { navigate } from '../router';
import { CaseViewPage } from './CaseViewPage';

export function LatestResultPage() {
  const { state, cases, error, reload } = useCaseList();

  if (state === 'loading') {
    return (
      <div className="page">
        <PageHeader title="Screening result" subtitle="Opening the most recent screening…" />
        <LoadingBlock label="Loading the latest screening result…" />
      </div>
    );
  }

  if (state === 'error') {
    return (
      <div className="page">
        <PageHeader title="Screening result" subtitle="Most recent screening on the backend" />
        <Alert variant="error" title={error?.title ?? 'Result unavailable'}>
          {error?.detail ??
            'The latest result could not be loaded while the backend is unreachable.'}
        </Alert>
        <div className="btn-row">
          <Button icon="refresh" onClick={reload}>
            Try again
          </Button>
          <Button variant="ghost" icon="grid" onClick={() => navigate('/dashboard')}>
            Back to dashboard
          </Button>
        </div>
      </div>
    );
  }

  if (cases.length === 0) {
    return (
      <div className="page">
        <PageHeader
          eyebrow="Screening result"
          title="Screening result"
          subtitle="The most recent screening opens here as soon as one exists."
        />
        <EmptyState
          icon="activity"
          title="No result yet"
          action={
            <Button variant="primary" icon="plus" onClick={() => navigate('/screening')}>
              Start a new screening
            </Button>
          }
        >
          No screening has been run. Results appear here as soon as a case goes through
          the quality gate and AI grading.
        </EmptyState>
      </div>
    );
  }

  return <CaseViewPage caseId={cases[0].caseId} />;
}
