/**
 * Report section. Requests the backend report artifact via POST (idempotent
 * generate); if it cannot be produced yet (no screening run), says so honestly.
 */
import { useState } from 'react';
import type { ReportResponse } from '../api/types';
import { fetchReportPdf, generateReport } from '../api/endpoints';
import { friendlyError } from '../utils/errors';
import { downloadBlob } from '../utils/download';
import { Alert } from './ui/Alert';
import { Button } from './ui/Button';
import { Card, CardBody, CardHeader } from './ui/Card';
import { LoadingState } from './ui/Skeleton';

export function ReportSection({ caseId }: { caseId: string }) {
  const [report, setReport] = useState<ReportResponse | null>(null);
  const [state, setState] = useState<'idle' | 'loading' | 'done' | 'error'>('idle');
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);
  const [pdfState, setPdfState] = useState<'idle' | 'loading' | 'error'>('idle');

  async function load() {
    setState('loading');
    setError(null);
    try {
      const r = await generateReport(caseId);
      setReport(r);
      setState('done');
    } catch (err) {
      const f = friendlyError(err);
      setError(f);
      setState('error');
    }
  }

  async function downloadPdf() {
    setPdfState('loading');
    try {
      const blob = await fetchReportPdf(caseId);
      downloadBlob(blob, `RetinaSense-report-${caseId}.pdf`);
      setPdfState('idle');
    } catch (err) {
      const f = friendlyError(err);
      setError(f);
      setPdfState('error');
    }
  }

  return (
    <Card aria-label="Report">
      <CardHeader
        title="Screening report"
        subtitle="Assembled by the backend from the stored screening records"
        icon="file"
        bordered
      />
      <CardBody>
        {state === 'idle' && (
          <>
            <p className="note-text">
              The report is generated from the real stored quality, AI, review and
              decision records. Nothing is composed in the browser.
            </p>
            <div className="btn-row">
              <Button variant="primary" icon="file" onClick={() => void load()}>
                Load report
              </Button>
            </div>
          </>
        )}

        {state === 'loading' && <LoadingState label="Loading report…" />}

        {state === 'done' && report && (
          <>
            <p className="note-text">
              Case <strong>{report.caseId}</strong>
            </p>
            {report.summary && <p className="report-summary">{report.summary}</p>}
            {report.disclaimer && <p className="note-text">{report.disclaimer}</p>}
            <div className="btn-row">
              <Button icon="refresh" onClick={() => void load()}>
                Regenerate report
              </Button>
              <Button
                variant="primary"
                icon="download"
                loading={pdfState === 'loading'}
                onClick={() => void downloadPdf()}
              >
                {pdfState === 'loading' ? 'Preparing PDF…' : 'Download PDF'}
              </Button>
            </div>
            {pdfState === 'error' && error && (
              <Alert variant="error" title={error.title}>{error.detail}</Alert>
            )}
          </>
        )}

        {state === 'error' && error && (
          <>
            <Alert variant="error" title={error.title}>{error.detail}</Alert>
            <div className="btn-row">
              <Button icon="refresh" onClick={() => void load()}>
                Try again
              </Button>
            </div>
          </>
        )}
      </CardBody>
    </Card>
  );
}
