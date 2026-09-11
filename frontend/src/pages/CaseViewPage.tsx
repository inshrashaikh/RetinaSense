/**
 * Case view — quality gate, immutable AI prediction, explainability, human
 * review, and final decision.
 */
import { useCallback, useEffect, useState } from 'react';
import { getCase } from '../api/endpoints';
import type { AiPrediction, CaseResponse, HumanReview, ReviewResponse } from '../api/types';
import { AiPredictionPanel } from '../components/AiPredictionPanel';
import { ErrorBanner } from '../components/ErrorBanner';
import { ExplainabilityPanel } from '../components/ExplainabilityPanel';
import { FinalDecisionPanel } from '../components/FinalDecisionPanel';
import { ImagePreview } from '../components/ImagePreview';
import { LoadingIndicator } from '../components/LoadingIndicator';
import { QualityPanel } from '../components/QualityPanel';
import { ReportSection } from '../components/ReportSection';
import { ReviewPanel } from '../components/ReviewPanel';
import { StatusPill } from '../components/StatusPill';
import { friendlyError } from '../utils/errors';
import { navigate } from '../router';

type FetchState = 'loading' | 'done' | 'error';

export function CaseViewPage({ caseId }: { caseId: string }) {
  const [state, setState] = useState<FetchState>('loading');
  const [data, setData] = useState<CaseResponse | null>(null);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);
  const [reviewNotice, setReviewNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState('loading');
    setError(null);
    try {
      const c = await getCase(caseId);
      setData(c);
      setState('done');
    } catch (err) {
      const f = friendlyError(err);
      setError(f);
      setState('error');
    }
  }, [caseId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function onReviewSubmitted(_res: ReviewResponse) {
    await load();
    setReviewNotice('Review recorded. The final decision above reflects the human review; the AI prediction is unchanged.');
  }

  if (state === 'loading') {
    return <LoadingIndicator label={`Loading case ${caseId}…`} />;
  }

  if (state === 'error' || !data) {
    return (
      <div className="page">
        <h1>Case {caseId}</h1>
        {error && <ErrorBanner title={error.title} detail={error.detail} />}
        <button type="button" className="btn" onClick={() => navigate('/')}>
          Back to dashboard
        </button>
        <button type="button" className="btn" onClick={() => void load()}>
          Try again
        </button>
      </div>
    );
  }

  const ai: AiPrediction | null = data.aiPrediction;
  const review: HumanReview | null = data.humanReview;
  const recapture = data.status === 'recapture_required' || data.quality.class === 'ungradable';
  const aiReady = ai !== null && ai.grade !== null;

  return (
    <div className="page">
      <div className="case-head">
        <h1>Case {data.caseId}</h1>
        <StatusPill
          tone={recapture ? 'warn' : 'info'}
          label={recapture ? 'Recapture requested' : data.status}
        />
      </div>

      {reviewNotice && (
        <div className="notice-ok" role="status">
          {reviewNotice}
        </div>
      )}
      {error && <ErrorBanner title={error.title} detail={error.detail} />}

      <div className="case-grid">
        <div className="case-column">
          <section className="panel" aria-label="Fundus image">
            <h2 className="panel-title">Fundus image</h2>
            <ImagePreview caseId={caseId} />
          </section>
          <QualityPanel quality={data.quality} />
        </div>

        <div className="case-column">
          {recapture && (
            <section className="panel" aria-label="Recapture note">
              <h2 className="panel-title">Recapture required</h2>
              <p className="empty-note">
                This image does not pass the quality gate, so it was not
                graded. Take a new photo following the instruction above, then
                start a new screening. The AI result and report sections are
                intentionally blank — nothing is fabricated for an ungradable image.
              </p>
            </section>
          )}
          <AiPredictionPanel ai={recapture ? null : data.aiPrediction} />
          <ExplainabilityPanel explain={data.explainability} />
        </div>
      </div>

      <FinalDecisionPanel ai={recapture ? null : data.aiPrediction} fd={data.finalDecision} review={review} />

      {!recapture && !review && aiReady && (
        <ReviewPanel caseId={caseId} ai={ai} onSubmitted={(r) => void onReviewSubmitted(r)} onError={(title, detail) => setError({ title, detail })} />
      )}

      {!recapture && <ReportSection caseId={caseId} />}

      <div className="btn-row">
        <button type="button" className="btn" onClick={() => navigate('/')}>
          Back to dashboard
        </button>
        <button type="button" className="btn" onClick={() => navigate('/screening')}>
          Start another screening
        </button>
      </div>
    </div>
  );
}