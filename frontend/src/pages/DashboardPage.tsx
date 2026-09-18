/**
 * DashboardPage — role dispatcher.
 *
 * Signed-in users land on a dashboard tailored to what their role can do:
 *   * phc_operator   → capture/screening operations (no review controls)
 *   * ophthalmologist → clinical review with AI briefs
 *   * admin           → system monitoring
 *
 * With no role (DEMO mode or an unknown session) it falls back to the generic
 * console. Dispatching on the client is a UX concern only — the backend still
 * enforces every role on each request.
 */
import { getUser } from '../auth/session';
import { AdminDashboard } from './dashboards/AdminDashboard';
import { DoctorDashboard } from './dashboards/DoctorDashboard';
import { OperatorDashboard } from './dashboards/OperatorDashboard';
import { ScreeningConsole } from './dashboards/ScreeningConsole';

export function DashboardPage({ demoMode }: { demoMode: boolean }) {
  const user = demoMode ? null : getUser();
  const role = user?.role;

  switch (role) {
    case 'phc_operator':
      return <OperatorDashboard />;
    case 'ophthalmologist':
      return <DoctorDashboard />;
    case 'admin':
      return <AdminDashboard />;
    default:
      return <ScreeningConsole demoMode={demoMode} />;
  }
}
