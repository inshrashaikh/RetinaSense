/**
 * Report detail — the full screening report for one case, assembled from the
 * real backend report artifact. Shows case information, image, quality, AI
 * grade/confidence/uncertainty, referable decision, explainability status,
 * human review, the final decision, and the report disclaimer.
 *
 * Nothing is invented here: if the backend cannot produce the report, the page
 * says so and offers a retry.
 */
import { useCallback, useEffect, useState } from 'react';
import { generateReport, getCase } from '../api/endpoints';
import type { CaseResponse, ReportResponse } from '../api/types';
import { hasPrediction } from '../api/types';
import { AiPredictionPanel } from '../components/AiPredictionPanel';
import { ErrorBanner } from '../components/ErrorBanner';
import { ExplainabilityPanel } from '../components/ExplainabilityPanel';
import { FinalDecisionPanel } from '../components/FinalDecisionPanel';
import { ImagePreview } from '../components/ImagePreview';
import { QualityPanel } from '../components/QualityPanel';
import { StatusPill } from '../components/StatusPill';
import { Alert } from '../components/ui/Alert';
import { Breadcrumbs } from '../components/ui/Breadcrumbs';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader, Row } from '../components/ui/Card';
import { PageHeader } from '../components/ui/PageHeader';
import { LoadingBlock } from '../components/ui/Skeleton';
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
    return (
      <div className="page">
        <Breadcrumbs items={[{ label: 'Reports', path: '/reports' }, { label: caseId }]} />
        <PageHeader title={`Screening report · ${caseId}`} subtitle="Assembling the report…" />
        <LoadingBlock label={`Generating report for case ${caseId}…`} />
      </div>
    );
  }

  if (state === 'error' || !caseData) {
    return (
      <div className="page">
        <Breadcrumbs items={[{ label: 'Reports', path: '/reports' }, { label: caseId }]} />
        <PageHeader
          title={`Screening report · ${caseId}`}
          subtitle="The report could not be loaded from the backend."
        />
        {error && <ErrorBanner title={error.title} detail={error.detail} />}
        <div className="btn-row">
          <Button variant="primary" icon="arrowLeft" onClick={() => navigate('/reports')}>
            Back to reports
          </Button>
          <Button icon="refresh" onClick={() => void load()}>
            Try again
          </Button>
        </div>
      </div>
    );
  }

  const payload = (report?.report ?? {}) as ReportPayload;
  const quality = payload.quality ?? caseData.quality;
  const rawAi = payload.aiPrediction ?? caseData.aiPrediction;
  const ai = hasPrediction(rawAi) ? rawAi : null;
  const explain = payload.explainability ?? caseData.explainability;
  const review = payload.humanReview ?? caseData.humanReview;
  const finalDecision = payload.finalDecision ?? caseData.finalDecision;
  const effectiveStatus = payload.status ?? caseData.status;

  return (
    <div className="page">
      <Breadcrumbs
        items={[
          { label: 'Reports', path: '/reports' },
          { label: 'Report', path: undefined },
          { label: caseId },
        ]}
      />

      <PageHeader
        eyebrow="Structured screening report"
        title={`Screening report · ${caseId}`}
        subtitle={`Report for case ${caseId}, assembled by the backend from the stored
          screening and review records.`}
        badges={<StatusPill tone={statusTone(effectiveStatus)} label={statusLabel(effectiveStatus)} />}
        actions={
          <>
            <Button icon="print" onClick={() => window.print()}>
              Print
            </Button>
            <Button icon="layers" onClick={() => navigate(`/case/${caseId}`)}>
              Open case
            </Button>
          </>
        }
      />

      {!report && error && (
        <Alert
          variant="warning"
          icon="alert"
          title={error.title}
          role="alert"
          action={
            <Button size="sm" icon="refresh" onClick={() => void load()}>
              Retry report generation
            </Button>
          }
        >
          {error.detail} Nothing is displayed in place of a report; the sections below are the
          stored case record itself.
        </Alert>
      )}

      <Card aria-label="Case information">
        <CardHeader
          title="Case information"
          subtitle="Identifiers recorded with this case"
          icon="clipboard"
          bordered
        />
        <CardBody>
          <div className="rows">
            <Row label="Case ID">{caseId}</Row>
            <Row label="Patient ID">{payload.patientId || '—'}</Row>
            <Row label="Eye">{payload.eye || '—'}</Row>
            <Row label="PHC">{payload.phcId || '—'}</Row>
            <Row label="Status">{statusLabel(effectiveStatus)}</Row>
          </div>
        </CardBody>
      </Card>

      <div className="grid-2">
        <div className="page-stack">
          <Card aria-label="Fundus image">
            <CardHeader title="Fundus image" subtitle="Stored with the case" icon="image" bordered />
            <CardBody>
              <ImagePreview caseId={caseId} />
            </CardBody>
          </Card>
          <QualityPanel quality={quality} />
        </div>
        <div className="page-stack">
          <AiPredictionPanel ai={ai} />
          <ExplainabilityPanel explain={explain} />
        </div>
      </div>

      <FinalDecisionPanel ai={ai} fd={finalDecision} review={review} />

      {report?.summary && (
        <Card aria-label="Report summary">
          <CardHeader
            title="Report summary"
            subtitle="Narrative assembled by the reporting stage"
            icon="file"
            bordered
          />
          <CardBody>
            <p className="report-summary">{report.summary}</p>
          </CardBody>
        </Card>
      )}

      {report?.disclaimer && (
        <Alert variant="neutral" title="Disclaimer" icon="shieldCheck" role="note">
          {report.disclaimer}
        </Alert>
      )}

      <footer className="report-footer">
        <p className="note-text">
          Report reference: <strong>{caseId}</strong> · Status: {statusLabel(effectiveStatus)} ·
          Confidence: {ai && ai.confidence !== null ? formatPercent(ai.confidence) : '—'}
        </p>
      </footer>

      <div className="btn-row">
        <Button icon="arrowLeft" onClick={() => navigate('/reports')}>
          Back to reports
        </Button>
        <Button variant="ghost" icon="layers" onClick={() => navigate(`/case/${caseId}`)}>
          Open case
        </Button>
      </div>
    </div>
  );
}
