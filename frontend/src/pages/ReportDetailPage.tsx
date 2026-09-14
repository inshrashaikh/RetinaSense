/**
 * Report detail page — full screening report for one case, assembled from the
 * real backend report artifact (POST /api/cases/{caseId}/report). Shows case
 * information, image, quality, AI grade/confidence/uncertainty, referable
 * decision, explainability status, human review, the final decision, and the
 * report disclaimer. Nothing is invented here.
 */
import { useCallback, useEffect, useState } from 'react';
import { generateReport, getCase } from '../api/endpoints';
import type { CaseResponse, ReportResponse } from '../api/types';
import { AiPredictionPanel } from '../components/AiPredictionPanel';
import { ErrorBanner } from '../components/ErrorBanner';
import { ExplainabilityPanel } from '../components/ExplainabilityPanel';
import { FinalDecisionPanel } from '../components/FinalDecisionPanel';
import { ImagePreview } from '../components/ImagePreview';
import { LoadingIndicator } from '../components/LoadingIndicator';
import { QualityPanel } from '../components/QualityPanel';
import { StatusPill } from '../components/StatusPill';
import { navigate } from '../router';
import { friendlyError } from '../utils/errors';
import { formatPercent, statusLabel, statusTone } from '../utils/format';

type FetchState = 'loading' | 'done' | 'error';

interface ReportPayload {
  caseId?: string;
  status?: string;
  patientId?: string;
  eye?: string;
  phcId?: string;
  quality?: CaseResponse['quality'];
  aiPrediction?: CaseResponse['aiPrediction'];
  explainability?: CaseResponse['explainability'];
  humanReview?: CaseResponse['humanReview'];
  finalDecision?: CaseResponse['finalDecision'];
}

export function ReportDetailPage({ caseId }: { caseId: string }) {
  const [state, setState] = useState<FetchState>('loading');
  const [caseData, setCaseData] = useState<CaseResponse | null>(null);
  const [report, setReport] = useState<ReportResponse | null>(null);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);

  const load = useCallback(async () => {
    setState('loading');
    setError(null);
    try {
      const c = await getCase(caseId);
      setCaseData(c);
      try {
        const r = await generateReport(caseId);
        setReport(r);
      } catch (reportErr) {
        setReport(null);
        setError(friendlyError(reportErr));
      }
      setState('done');
    } catch (err) {
      setError(friendlyError(err));
      setState('error');
    }
  }, [caseId]);

  useEffect(() => {
    void load();
  }, [load]);

  if (state === 'loading') {
    return <LoadingIndicator label={`Generating report for case ${caseId}…`} />;
  }

  if (state === 'error' || !caseData) {
    return (
      <div className="page">
        <h1>Report — {caseId}</h1>
        {error && <ErrorBanner title={error.title} detail={error.detail} />}
        <div className="btn-row">
          <button type="button" className="btn" onClick={() => navigate('/reports')}>
            Back to reports
          </button>
          <button type="button" className="btn" onClick={() => void load()}>
            Try again
          </button>
        </div>
      </div>
    );
  }

  const payload = (report?.report ?? {}) as ReportPayload;
  const quality = payload.quality ?? caseData.quality;
  const ai = payload.aiPrediction ?? caseData.aiPrediction;
  const explain = payload.explainability ?? caseData.explainability;
  const review = payload.humanReview ?? caseData.humanReview;
  const finalDecision = payload.finalDecision ?? caseData.finalDecision;
  const effectiveStatus = payload.status ?? caseData.status;

  return (
    <div className="page">
      <div className="case-head">
        <h1>Screening report · {caseId}</h1>
        <StatusPill tone={statusTone(effectiveStatus)} label={statusLabel(effectiveStatus)} />
      </div>
      <p className="page-intro">
        Structured report for case {caseId}, assembled by the backend from the
        stored screening and review records.
      </p>

      {error && <ErrorBanner title={error.title} detail={error.detail} />}

      <section className="panel" aria-label="Case information">
        <h2 className="panel-title">Case information</h2>
        <div className="panel-row">
          <span className="panel-label">Case ID</span>
          <span className="panel-value">{caseId}</span>
        </div>
        <div className="panel-row">
          <span className="panel-label">Patient ID</span>
          <span className="panel-value">{payload.patientId || '—'}</span>
        </div>
        <div className="panel-row">
          <span className="panel-label">Eye</span>
          <span className="panel-value">{payload.eye || '—'}</span>
        </div>
        <div className="panel-row">
          <span className="panel-label">PHC</span>
          <span className="panel-value">{payload.phcId || '—'}</span>
        </div>
      </section>

      <div className="case-grid">
        <div className="case-column">
          <section className="panel" aria-label="Fundus image">
            <h2 className="panel-title">Fundus image</h2>
            <ImagePreview caseId={caseId} />
          </section>
          <QualityPanel quality={quality} />
        </div>
        <div className="case-column">
          <AiPredictionPanel ai={ai} />
          <ExplainabilityPanel caseId={caseId} explain={explain} />
        </div>
      </div>

      <FinalDecisionPanel ai={ai} fd={finalDecision} review={review} />

      {report?.summary && (
        <section className="panel" aria-label="Report summary">
          <h2 className="panel-title">Report summary</h2>
          <p className="report-summary">{report.summary}</p>
        </section>
      )}

      {report?.disclaimer && (
        <section className="panel" aria-label="Report disclaimer">
          <h2 className="panel-title">Disclaimer</h2>
          <p className="note-text">{report.disclaimer}</p>
        </section>
      )}

      {!report && (
        <section className="panel" aria-label="Report unavailable">
          <h2 className="panel-title">Report unavailable</h2>
          <p className="empty-note">
            No report could be generated for this case. Check that a screening was
            completed, then try again.
          </p>
          <button type="button" className="btn" onClick={() => void load()}>
            Retry report generation
          </button>
        </section>
      )}

      <footer className="report-footer">
        <p className="note-text">
          Report reference: <strong>{caseId}</strong> · Status: {statusLabel(effectiveStatus)} ·
          Confidence: {ai && ai.confidence !== null ? formatPercent(ai.confidence) : '—'}
        </p>
      </footer>

      <div className="btn-row">
        <button type="button" className="btn" onClick={() => navigate('/reports')}>
          Back to reports
        </button>
        <button type="button" className="btn" onClick={() => navigate(`/case/${caseId}`)}>
          Open case
        </button>
      </div>
    </div>
  );
}