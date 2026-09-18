/**
 * useSimulationCapacity — loader for the measured district-capacity results
 * (GET /api/simulation/capacity, admin only).
 *
 * When no Simulink output exists the backend reports `available: false` and
 * this hook simply surfaces that — it never substitutes a number.
 */
import { useCallback, useEffect, useState } from 'react';
import { fetchSimulationCapacity } from '../api/endpoints';
import type { SimulationCapacityResponse } from '../api/types';
import { friendlyError, type FriendlyError } from '../utils/errors';

export type SimulationState = 'loading' | 'done' | 'unreachable';

export interface UseSimulationCapacity {
  state: SimulationState;
  data: SimulationCapacityResponse | null;
  error: FriendlyError | null;
  reload: () => void;
}

export function useSimulationCapacity(): UseSimulationCapacity {
  const [state, setState] = useState<SimulationState>('loading');
  const [data, setData] = useState<SimulationCapacityResponse | null>(null);
  const [error, setError] = useState<FriendlyError | null>(null);

  const load = useCallback(async () => {
    setState('loading');
    setError(null);
    try {
      const response = await fetchSimulationCapacity();
      setData(response);
      setState('done');
    } catch (err) {
      setError(friendlyError(err));
      setState('unreachable');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return { state, data, error, reload: () => void load() };
}