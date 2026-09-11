/**
 * Dashboard — branding, health indicator, live stats from the backend,
 * AI-assisted + human-in-the-loop callout, and recent cases.
 */
import { DashboardStats } from '../components/DashboardStats';
import { DemoScenarioSelect } from '../components/DemoScenarioSelect';
import { RecentCases } from '../components/RecentCases';
import { navigate } from '../router';

export function DashboardPage({ demoMode }: { demoMode: boolean }) {
  return (
    <div className="page">
      <section className="hero" aria-label="Get started">
        <h1>RetinaSense screening console</h1>
        <p>
          AI-assisted diabetic retinopathy screening with a human-in-the-loop final
          decision. Upload a fundus image, run the deterministic quality gate and AI
          grading, then an ophthalmologist approves, overrides, or requests a
          recapture before any final referral is recorded.
        </p>
        <div className="hero-actions">
          <button type="button" className="btn btn-primary btn-lg" onClick={() => navigate('/screening')}>
            New screening
          </button>
        </div>
      </section>

      {demoMode && <DemoScenarioSelect />}

      <DashboardStats />
      <RecentCases />
    </div>
  );
}