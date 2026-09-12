/**
 * App — routing.
 *
 * `#/` is the public landing page (rendered outside the application shell).
 * Every other route renders inside the AppShell. Dynamic case/report paths are
 * parsed by the same helpers as before.
 */
import { useEffect } from 'react';
import { AppShell } from './components/AppShell';
import {
  useHashPath,
  caseIdFromPath,
  caseUploadFromPath,
  reportIdFromPath,
} from './router';
import { isDemoMode } from './api/endpoints';
import { CasesPage } from './pages/CasesPage';
import { CaseUploadPage } from './pages/CaseUploadPage';
import { CaseViewPage } from './pages/CaseViewPage';
import { CreateCasePage } from './pages/CreateCasePage';
import { DashboardPage } from './pages/DashboardPage';
import { LandingPage } from './pages/LandingPage';
import { LatestResultPage } from './pages/LatestResultPage';
import { NewScreeningPage } from './pages/NewScreeningPage';
import { NotFoundPage } from './pages/NotFoundPage';
import { ReportDetailPage } from './pages/ReportDetailPage';
import { ReportsPage } from './pages/ReportsPage';
import { ReviewQueuePage } from './pages/ReviewQueuePage';

export default function App() {
  const path = useHashPath();
  const demoMode = isDemoMode;

  // Start each route at the top of the page.
  useEffect(() => {
    window.scrollTo({ top: 0 });
  }, [path]);

  if (path === '/') {
    return <LandingPage demoMode={demoMode} />;
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
