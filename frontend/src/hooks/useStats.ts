/**
 * useStats — one shared loader for the backend-derived dashboard metrics.
 *
 * Reads aggregate counts from GET /api/cases/stats and engine state from
 * GET /api/health. When the backend is unreachable the hook reports that
 * honestly; it never substitutes zeros for unknown values.
 */
import { useCallback, useEffect, useState } from 'react';
import { fetchCaseStats, fetchHealth } from '../api/endpoints';
import type { CaseStats, HealthResponse } from '../api/types';

export type StatsState = 'loading' | 'done' | 'unreachable';

export interface UseStats {
  state: StatsState;
  stats: CaseStats | null;
  health: HealthResponse | null;
  reload: () => void;
}

export function useStats(): UseStats {
  const [stats, setStats] = useState<CaseStats | null>(null);
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [state, setState] = useState<StatsState>('loading');

  const load = useCallback(async () => {
    setState('loading');
    try {
      const [s, h] = await Promise.all([fetchCaseStats(), fetchHealth()]);
      setStats(s);
      setHealth(h);
      setState('done');
    } catch {
      setState('unreachable');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return { state, stats, health, reload: () => void load() };
}
