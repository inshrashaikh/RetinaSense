/**
 * App shell + hash routing.
 */
import { Layout } from './components/Layout';
import { useHashPath, caseIdFromPath, reportIdFromPath, navigate } from './router';
import { isDemoMode } from './api/endpoints';
import { CasesPage } from './pages/CasesPage';
import { DashboardPage } from './pages/DashboardPage';
import { CaseViewPage } from './pages/CaseViewPage';
import { LatestResultPage } from './pages/LatestResultPage';
import { NewScreeningPage } from './pages/NewScreeningPage';
import { ReportsPage } from './pages/ReportsPage';
import { ReportDetailPage } from './pages/ReportDetailPage';
import { ReviewQueuePage } from './pages/ReviewQueuePage';

export default function App() {
  const path = useHashPath();
  const demoMode = isDemoMode;

  const caseId = caseIdFromPath(path);
  const reportCaseId = reportIdFromPath(path);

  let page: React.ReactNode;
  if (caseId) {
    page = <CaseViewPage caseId={caseId} />;
  } else if (reportCaseId) {
    page = <ReportDetailPage caseId={reportCaseId} />;
  } else if (path === '/screening') {
    page = <NewScreeningPage />;
  } else if (path === '/cases') {
    page = <CasesPage />;
  } else if (path === '/result') {
    page = <LatestResultPage />;
  } else if (path === '/review') {
    page = <ReviewQueuePage />;
  } else if (path === '/reports') {
    page = <ReportsPage />;
  } else if (path === '/' || path === '') {
    page = <DashboardPage demoMode={demoMode} />;
  } else {
    page = (
      <div className="page">
        <h1>Page not found</h1>
        <p className="page-intro">No route matches <code>{path}</code>.</p>
        <button type="button" className="btn btn-primary" onClick={() => navigate('/')}>
          Back to dashboard
        </button>
      </div>
    );
  }

  return <Layout demoMode={demoMode}>{page}</Layout>;
}