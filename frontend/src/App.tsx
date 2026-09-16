/**
 * App — routing.
 *
 * `#/` is the public landing page (rendered outside the application shell).
 * `#/login` is the standalone sign-in screen. Every other route renders inside
 * the AppShell and requires an authenticated session (unless DEMO mode is on).
 * Role-gated routes (e.g. the review queue) redirect when the signed-in role
 * is not allowed.
 */
import { useEffect, useState } from 'react';
import { AppShell } from './components/AppShell';
import {
  useHashPath,
  caseIdFromPath,
  caseUploadFromPath,
  navigate,
  reportIdFromPath,
} from './router';
import { isDemoMode } from './api/endpoints';
import { canReview, getUser, isAuthenticated, subscribeAuth } from './auth/session';
import { CasesPage } from './pages/CasesPage';
import { CaseUploadPage } from './pages/CaseUploadPage';
import { CaseViewPage } from './pages/CaseViewPage';
import { CreateCasePage } from './pages/CreateCasePage';
import { DashboardPage } from './pages/DashboardPage';
import { LandingPage } from './pages/LandingPage';
import { LatestResultPage } from './pages/LatestResultPage';
import { LoginPage } from './pages/LoginPage';
import { NewScreeningPage } from './pages/NewScreeningPage';
import { NotFoundPage } from './pages/NotFoundPage';
import { ReportDetailPage } from './pages/ReportDetailPage';
import { ReportsPage } from './pages/ReportsPage';
import { ReviewQueuePage } from './pages/ReviewQueuePage';

/**
 * Re-render whenever a session is saved or cleared (login/logout), so the auth
 * gate reflects the current session without a page reload.
 */
function useAuthTick(): void {
  const [, setTick] = useState(0);
  useEffect(() => subscribeAuth(() => setTick((n) => n + 1)), []);
}

export default function App() {
  const path = useHashPath();
  const demoMode = isDemoMode;

  // Re-render on login/logout so protected routes unlock immediately.
  useAuthTick();

  // Start each route at the top of the page.
  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [path]);

  if (path === '/') {
    return <LandingPage demoMode={demoMode} />;
  }

  // Auth gate — skipped entirely in DEMO mode (there is no backend session).
  // An already-signed-in user visiting /login is sent straight to the console.
  if (!demoMode) {
    if (path === '/login') {
      if (isAuthenticated()) {
        navigate('/dashboard');
        return null;
      }
      return <LoginPage />;
    }
    if (!isAuthenticated()) {
      return <LoginPage />;
    }
  }

  // Role-gate: the review queue is clinical-review work (ophthalmologist/admin).
  if (!demoMode && path === '/review' && !canReview(getUser()?.role)) {
    navigate('/dashboard');
    return null;
  }

  const caseId = caseIdFromPath(path);
  const uploadCaseId = caseUploadFromPath(path);
  const reportCaseId = reportIdFromPath(path);

  let page: React.ReactNode;
  if (uploadCaseId) {
    page = <CaseUploadPage caseId={uploadCaseId} />;
  } else if (caseId) {
    page = <CaseViewPage caseId={caseId} />;
  } else if (reportCaseId) {
    page = <ReportDetailPage caseId={reportCaseId} />;
  } else if (path === '/dashboard') {
    page = <DashboardPage demoMode={demoMode} />;
  } else if (path === '/screening') {
    page = <NewScreeningPage />;
  } else if (path === '/cases/new') {
    page = <CreateCasePage />;
  } else if (path === '/cases') {
    page = <CasesPage />;
  } else if (path === '/result') {
    page = <LatestResultPage />;
  } else if (path === '/review') {
    page = <ReviewQueuePage />;
  } else if (path === '/reports') {
    page = <ReportsPage />;
  } else {
    page = <NotFoundPage path={path} />;
  }

  return <AppShell demoMode={demoMode}>{page}</AppShell>;
}