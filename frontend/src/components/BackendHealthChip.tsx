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
    return <span className="health-chip health-loading">Checking backend…</span>;
  }
  if (state === 'unreachable') {
    return (
      <span className="health-chip health-bad" role="note">
        Backend unreachable — real screening unavailable
      </span>
    );
  }
  return (
    <span className={`health-chip ${health?.matlabEngine ? 'health-good' : 'health-warn'}`} role="note">
      Backend reachable · MATLAB AI engine {health?.matlabEngine ? 'connected' : 'not connected'}
    </span>
  );
}