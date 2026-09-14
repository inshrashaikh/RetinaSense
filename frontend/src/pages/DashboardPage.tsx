/**
 * Dashboard — the clinical command centre.
 *
 * Everything on this page is derived from the backend: case counts from
 * GET /api/cases/stats, worklists from GET /api/cases, engine state from
 * GET /api/health.
 */
import { DashboardCases } from '../components/DashboardCases';
import { DashboardStats } from '../components/DashboardStats';
import { DemoScenarioSelect } from '../components/DemoScenarioSelect';
import { Button } from '../components/ui/Button';
import { PageHeader } from '../components/ui/PageHeader';
import { navigate } from '../router';

export function DashboardPage({ demoMode }: { demoMode: boolean }) {
  return (
    <div className="page">
      <PageHeader
        eyebrow="Clinical console"
        title="RetinaSense screening console"
        subtitle="AI-assisted diabetic retinopathy screening with a human-in-the-loop final
          decision. Upload a fundus image, run the deterministic quality gate and AI
          grading, then review the case before any referral is recorded."
        actions={
          <>
            <Button icon="layers" onClick={() => navigate('/cases')}>
              Browse cases
            </Button>
            <Button variant="primary" size="lg" icon="plus" onClick={() => navigate('/screening')}>
              New screening
            </Button>
          </>
        }
      />

      {demoMode && <DemoScenarioSelect />}

      <DashboardStats />
      <DashboardCases />
    </div>
  );
}
