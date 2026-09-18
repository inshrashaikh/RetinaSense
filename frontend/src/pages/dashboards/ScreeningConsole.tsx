/**
 * ScreeningConsole — the generic dashboard used when there is no role to
 * dispatch on (DEMO mode, or a session whose role is unknown).
 *
 * It is the original combined console: backend stats plus the operational case
 * worklists. Signed-in users get a role-specific dashboard instead (see
 * DashboardPage).
 */
import { DashboardCases } from '../../components/DashboardCases';
import { DashboardStats } from '../../components/DashboardStats';
import { DemoScenarioSelect } from '../../components/DemoScenarioSelect';
import { Button } from '../../components/ui/Button';
import { PageHeader } from '../../components/ui/PageHeader';
import { navigate } from '../../router';

export function ScreeningConsole({ demoMode }: { demoMode: boolean }) {
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
