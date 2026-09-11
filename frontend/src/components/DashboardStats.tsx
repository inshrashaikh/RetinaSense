/**
 * Dashboard stat cards + AI-assisted / human-in-the-loop pipeline indicator.
 * Counts come from the backend (GET /api/cases/stats); when the backend is
 * unreachable the cards show an honest "unavailable" state instead of zeros.
 */
import { useEffect, useState } from 'react';
import { fetchCaseStats, fetchHealth } from '../api/endpoints';
import type { CaseStats, HealthResponse } from '../api/types';
import { BackendHealthChip } from './BackendHealthChip';

type StatsState = 'loading' | 'done' | 'unreachable';

function StatCard({
  label,
  value,
  note,
}: {
  label: string;
  value: number | string;
  note?: string;
}) {
  return (
    <div className="stat-card" aria-label={label}>
      <span className="stat-value">{value}</span>
      <span className="stat-label">{label}</span>
      {note && <span className="stat-note">{note}</span>}
    </div>
  );
}

export function DashboardStats() {
  const [stats, setStats] = useState<CaseStats | null>(null);
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [state, setState] = useState<StatsState>('loading');

  useEffect(() => {
    let alive = true;
    Promise.all([fetchCaseStats(), fetchHealth()])
      .then(([s, h]) => {
        if (!alive) return;
        setStats(s);
        setHealth(h);
        setState('done');
      })
      .catch(() => {
        if (alive) setState('unreachable');
      });
    return () => {
      alive = false;
    };
  }, []);

  if (state === 'loading') {
    return (
      <section className="panel" aria-label="Overview statistics">
        <h2 className="panel-title">Overview</h2>
        <div className="loading">
          <span className="loading-spinner" aria-hidden="true" />
          <span>Loading statistics…</span>
        </div>
      </section>
    );
  }

  if (state === 'unreachable' || !stats) {
    return (
      <section className="panel" aria-label="Overview statistics">
        <h2 className="panel-title">Overview</h2>
        <p className="empty-note">
          Statistics are unavailable while the backend is unreachable. Nothing is
          assumed in their place.
        </p>
        <div className="hero-status">
          <BackendHealthChip />
        </div>
      </section>
    );
  }

  return (
    <div className="panel">
      <div className="panel-head-row">
        <h2 className="panel-title">Overview</h2>
        <BackendHealthChip />
      </div>
      <div className="stat-grid">
        <StatCard label="Total cases" value={stats.totalCases} />
        <StatCard label="Screenings completed" value={stats.screeningsCompleted} />
        <StatCard label="Pending reviews" value={stats.pendingReviews} />
        <StatCard label="Reviewed" value={stats.reviewed} />
        <StatCard label="Recapture required" value={stats.recaptureRequired} />
        <StatCard label="Awaiting screening" value={stats.created} />
      </div>

      <div className="pipeline-strip" role="note" aria-label="Screening workflow">
        <span className="pipeline-step">1 · Quality gate</span>
        <span className="pipeline-arrow" aria-hidden="true">→</span>
        <span className="pipeline-step">2 · AI grading</span>
        <span className="pipeline-arrow" aria-hidden="true">→</span>
        <span className="pipeline-step">3 · Human review</span>
        <span className="pipeline-arrow" aria-hidden="true">→</span>
        <span className="pipeline-step pipeline-step-final">4 · Final referral decision</span>
      </div>
      <p className="note-text">
        AI-assisted screening with a human-in-the-loop final decision. The AI result is
        never overwritten by a reviewer; the final decision is stored separately.
        {health && health.matlabEngine ? '' : ' The MATLAB AI engine is not connected, so real screening is currently unavailable.'}
      </p>
    </div>
  );
}