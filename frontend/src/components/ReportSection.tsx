/**
 * Report section. Requests the backend report artifact via POST
 * (idempotent generate); if it cannot be produced yet (no screening run),
 * says so honestly.
 */
import { useState } from 'react';
import type { ReportResponse } from '../api/types';
import { generateReport } from '../api/endpoints';
import { friendlyError } from '../utils/errors';
import { LoadingIndicator } from './LoadingIndicator';

export function ReportSection({ caseId }: { caseId: string }) {
  const [report, setReport] = useState<ReportResponse | null>(null);
  const [state, setState] = useState<'idle' | 'loading' | 'done' | 'error'>('idle');
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);

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

  return (
    <section className="panel" aria-label="Report">
      <h2 className="panel-title">Screening report</h2>

      {state === 'idle' && (
        <button type="button" className="btn" onClick={load}>
          Load report
        </button>
      )}
      {state === 'loading' && <LoadingIndicator label="Loading report…" />}

      {state === 'done' && report && (
        <div className="panel-block">
          <p className="note-text">Case <strong>{report.caseId}</strong></p>
          {report.summary && <p className="report-summary">{report.summary}</p>}
          {report.disclaimer && <p className="note-text">{report.disclaimer}</p>}
          <button type="button" className="btn" onClick={load}>
            Regenerate report
          </button>
        </div>
      )}

      {state === 'error' && error && (
        <div className="panel-block">
          <p className="error-text">
            <strong>{error.title}.</strong> {error.detail}
          </p>
          <button type="button" className="btn" onClick={load}>
            Try again
          </button>
        </div>
      )}
    </section>
  );
}