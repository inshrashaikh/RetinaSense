/**
 * Backend health check. Reports the real connection state; never pretends the
 * MATLAB engine is available.
 */
import { useEffect, useState } from 'react';
import { fetchHealth } from '../api/endpoints';
import type { HealthResponse } from '../api/types';

type State = 'loading' | 'ok' | 'unreachable';

/** How often the bottom-left reachability indicator re-checks the backend. */
const HEALTH_POLL_MS = 10_000;

export function BackendHealthChip() {
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [state, setState] = useState<State>('loading');

  useEffect(() => {
    let alive = true;
    let currentlyUnreachable = false;

    async function check() {
      try {
        const h = await fetchHealth();
        if (!alive) return;
        currentlyUnreachable = false;
        setHealth(h);
        setState('ok');
      } catch {
        // After any failed poll the chip must reflect the live state — the
        // New screening page and this indicator share the same API base URL,
        // so an unreachable chip here means screening will fail too.
        if (!alive) return;
        if (!currentlyUnreachable) {
          currentlyUnreachable = true;
          setState('unreachable');
        }
      }
    }

    void check();
    const timer = setInterval(() => void check(), HEALTH_POLL_MS);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, []);

  if (state === 'loading') {
    return (
      <span className="health-chip">
        <span className="loading-spinner" aria-hidden="true" />
        Checking backend…
      </span>
    );
  }

  if (state === 'unreachable') {
    return (
      <span className="health-chip health-chip--bad" role="note">
        <span className="health-chip__dot" aria-hidden="true" />
        Backend unreachable — real screening unavailable
      </span>
    );
  }

  const engineUp = Boolean(health?.matlabEngine);
  return (
    <span
      className={`health-chip ${engineUp ? 'health-chip--good' : 'health-chip--warn'}`}
      role="note"
    >
      <span className="health-chip__dot" aria-hidden="true" />
      Backend reachable · MATLAB AI engine {engineUp ? 'connected' : 'not connected'}
    </span>
  );
}
