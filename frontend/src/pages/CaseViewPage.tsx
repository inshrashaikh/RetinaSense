/**
 * Case view — the full screening record.
 *
 * Layout order: case information → fundus image → image quality → AI prediction
 * → explainability → human review → final decision → report.
 *
 * The AI prediction and the human final decision are deliberately rendered as
 * separate, differently styled sections: the AI result is immutable and the
 * final decision is stored alongside it.
 */
import { useCallback, useEffect, useState } from 'react';
import { getCase } from '../api/endpoints';
import type { AiPrediction, CaseResponse, HumanReview, ReviewResponse } from '../api/types';
import { hasPrediction } from '../api/types';
import { AiPredictionPanel } from '../components/AiPredictionPanel';
import { ErrorBanner } from '../components/ErrorBanner';
import { ExplainabilityPanel } from '../components/ExplainabilityPanel';
import { FinalDecisionPanel } from '../components/FinalDecisionPanel';
import { ImagePreview } from '../components/ImagePreview';
import { QualityPanel } from '../components/QualityPanel';
import { ReportSection } from '../components/ReportSection';
import { ReviewPanel } from '../components/ReviewPanel';
import { StatusPill } from '../components/StatusPill';
import { Alert } from '../components/ui/Alert';
import { Badge } from '../components/ui/Badge';
import { Breadcrumbs } from '../components/ui/Breadcrumbs';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { PageHeader } from '../components/ui/PageHeader';
import { LoadingBlock } from '../components/ui/Skeleton';
import { friendlyError } from '../utils/errors';
import { statusLabel, statusTone } from '../utils/format';
import { navigate } from '../router';
import { getUser } from '../auth/session';

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
      setError(friendlyError(err));
      setState('error');
    }
  }, [caseId]);

  useEffect(() => {
    void load();
  }, [load]);

  async function onReviewSubmitted(_res: ReviewResponse) {
    await load();
    setReviewNotice(
      'Review recorded. The final decision above reflects the human review; the AI prediction is unchanged.',
    );
  }

  if (state === 'loading') {
    return (
      <div className="page">
        <Breadcrumbs items={[{ label: 'Cases', path: '/cases' }, { label: caseId }]} />
        <PageHeader title={`Case ${caseId}`} subtitle="Loading the screening record…" />
        <LoadingBlock label={`Loading case ${caseId}…`} />
      </div>
    );
  }

  if (state === 'error' || !data) {
    return (
      <div className="page">
        <Breadcrumbs items={[{ label: 'Cases', path: '/cases' }, { label: caseId }]} />
        <PageHeader title={`Case ${caseId}`} subtitle="The case record could not be loaded." />
        {error && <ErrorBanner title={error.title} detail={error.detail} />}
        <div className="btn-row">
          <Button variant="primary" icon="grid" onClick={() => navigate('/dashboard')}>
            Back to dashboard
          </Button>
          <Button icon="refresh" onClick={() => void load()}>
            Try again
          </Button>
        </div>
      </div>
    );
  }

  const ai: AiPrediction | null = data.aiPrediction;
  const review: HumanReview | null = data.humanReview;
  const recapture = data.status === 'recapture_required' || data.quality.class === 'ungradable';
  const aiReady = hasPrediction(ai);
  // Review is clinical work: hidden for capture-only operators. With no session
  // (demo mode) the form stays available — the backend enforces the role.
  const canDoReview = getUser()?.role !== 'phc_operator';
  // A report can only exist once the pipeline has actually screened the image;
  // offering "load report" for a created/never-screened case would be misleading.
  const screened = data.status !== 'created';

  return (
    <div className="page">
      <Breadcrumbs
        items={[
          { label: 'Cases', path: '/cases' },
          { label: 'Case', path: undefined },
          { label: caseId },
        ]}
      />

      <PageHeader
        eyebrow="Screening record"
        title={`Case ${caseId}`}
        subtitle="Quality assessment, the immutable AI result, the human review and the
          final decision — each recorded and displayed separately."
        badges={
          <>
            <StatusPill
              tone={recapture ? 'warn' : statusTone(data.status)}
              label={recapture ? 'Recapture requested' : statusLabel(data.status)}
            />
            {review && <Badge tone="good" icon="userCheck">Reviewed</Badge>}
          </>
        }
        actions={
          <>
            <Button icon="plus" onClick={() => navigate('/screening')}>
              Start another screening
            </Button>
            <Button icon="layers" onClick={() => navigate('/cases')}>
              All cases
            </Button>
          </>
        }
      />

      {reviewNotice && (
        <Alert variant="success" title="Review recorded" role="status">
          {reviewNotice}
        </Alert>
      )}
      {error && <ErrorBanner title={error.title} detail={error.detail} />}

      <Card aria-label="Case information">
        <CardHeader
          title="Case information"
          subtitle="Identifiers recorded by the backend for this case"
          icon="clipboard"
          bordered
        />
        <CardBody>
          <div className="meta-grid">
            <div className="meta">
              <span className="meta__label">Case ID</span>
              <span className="meta__value mono">{data.caseId}</span>
            </div>
            <div className="meta">
              <span className="meta__label">Status</span>
              <span className="meta__value">{statusLabel(data.status)}</span>
            </div>
            <div className="meta">
              <span className="meta__label">AI result</span>
              <span className="meta__value">{aiReady ? 'Produced' : 'Not produced'}</span>
            </div>
            <div className="meta">
              <span className="meta__label">Human review</span>
              <span className="meta__value">{review ? 'Recorded' : 'Not recorded'}</span>
            </div>
          </div>
        </CardBody>
      </Card>

      {recapture && (
        <Alert variant="warning" title="Recapture required">
          This image does not pass the quality gate, so it was not graded. Take a new
          photo following the instruction below, then start a new screening. The AI result
          and report sections are intentionally blank — nothing is fabricated for an
          ungradable image.
        </Alert>
      )}

      <div className="grid-2">
        <div className="page-stack">
          <Card aria-label="Fundus image">
            <CardHeader
              title="Fundus image"
              subtitle="Served by the backend for this case"
              icon="image"
              bordered
            />
            <CardBody>
              <ImagePreview caseId={caseId} />
            </CardBody>
          </Card>
          <QualityPanel quality={data.quality} />
        </div>

        <div className="page-stack">
          <AiPredictionPanel ai={recapture ? null : data.aiPrediction} />
          <ExplainabilityPanel caseId={caseId} explain={data.explainability} />
        </div>
      </div>

      <FinalDecisionPanel
        ai={recapture ? null : data.aiPrediction}
        fd={data.finalDecision}
        review={review}
      />

      {!recapture && !review && aiReady && canDoReview && (
        <ReviewPanel
          caseId={caseId}
          ai={ai}
          onSubmitted={(r) => void onReviewSubmitted(r)}
          onError={(title, detail) => setError({ title, detail })}
        />
      )}

      {!recapture && screened && <ReportSection caseId={caseId} />}

      <div className="btn-row">
        <Button icon="grid" onClick={() => navigate('/dashboard')}>
          Back to dashboard
        </Button>
        <Button variant="ghost" icon="plus" onClick={() => navigate('/screening')}>
          Start another screening
        </Button>
      </div>
    </div>
  );
}
