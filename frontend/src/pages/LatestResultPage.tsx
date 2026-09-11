/**
 * Screening result — opens the most recent case from the backend. With no
 * cases yet, shows an honest empty state. With cases, renders the case page
 * (quality gate → AI result → review → final decision).
 */
import { useEffect, useState } from 'react';
import { listCases } from '../api/endpoints';
import { LoadingIndicator } from '../components/LoadingIndicator';
import { navigate } from '../router';
import { CaseViewPage } from './CaseViewPage';

type Latest = string | null | 'none';

export function LatestResultPage() {
  const [latest, setLatest] = useState<Latest>(null);

  useEffect(() => {
    let alive = true;
    listCases()
      .then((items) => {
        if (!alive) return;
        setLatest(items.length > 0 ? items[0].caseId : 'none');
      })
      .catch(() => {
        if (alive) setLatest('none');
      });
    return () => {
      alive = false;
    };
  }, []);

  if (latest === null) {
    return <LoadingIndicator label="Loading the latest screening result…" />;
  }

  if (latest === 'none') {
    return (
      <div className="page">
        <h1>Screening result</h1>
        <section className="panel">
          <h2 className="panel-title">No result yet</h2>
          <p className="empty-note">
            No screening has been run. Results appear here as soon as a case goes
            through the quality gate and AI grading.
          </p>
          <div className="btn-row">
            <button type="button" className="btn btn-primary" onClick={() => navigate('/screening')}>
              Start a new screening
            </button>
          </div>
        </section>
      </div>
    );
  }

  return <CaseViewPage caseId={latest} />;
}