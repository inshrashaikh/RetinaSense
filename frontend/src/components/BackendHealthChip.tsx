/**
 * Backend health check. Reports the real connection state; never pretends the
 * MATLAB engine is available.
 */
import { useEffect, useState } from 'react';
import { fetchHealth } from '../api/endpoints';
import type { HealthResponse } from '../api/types';

type State = 'loading' | 'ok' | 'unreachable';

export function BackendHealthChip() {
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [state, setState] = useState<State>('loading');

  useEffect(() => {
    let alive = true;
    fetchHealth()
      .then((h) => {
        if (alive) {
          setHealth(h);
          setState('ok');
        }
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
