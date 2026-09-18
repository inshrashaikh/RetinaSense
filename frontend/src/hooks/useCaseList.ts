/**
 * useCaseList — one shared loader for the backend case list
 * (GET /api/cases) with explicit loading / loaded / error states.
 *
 * The list is always re-read from the backend; nothing is cached in the browser.
 */
import { useCallback, useEffect, useState } from 'react';
import { listCases } from '../api/endpoints';
import type { CaseListItem } from '../api/types';
import { friendlyError, type FriendlyError } from '../utils/errors';

export type CaseListState = 'loading' | 'done' | 'error';

export interface UseCaseList {
  state: CaseListState;
  cases: CaseListItem[];
  error: FriendlyError | null;
  reload: () => void;
}

export function useCaseList(): UseCaseList {
  const [state, setState] = useState<CaseListState>('loading');
  const [cases, setCases] = useState<CaseListItem[]>([]);
  const [error, setError] = useState<FriendlyError | null>(null);

  const load = useCallback(async () => {
    setState('loading');
    setError(null);
    try {
      const items = await listCases();
      setCases(items);
      setState('done');
    } catch (err) {
      setError(friendlyError(err));
      setState('error');
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return { state, cases, error, reload: () => void load() };
}

/** A case awaiting a human decision: screened with a recorded AI result. */
export function isAwaitingReview(c: CaseListItem): boolean {
  return c.status === 'completed';
}

/** A case whose image failed the quality gate and must be captured again. */
export function isRecaptureRequired(c: CaseListItem): boolean {
  return c.status === 'recapture_required';
}

/** A registered case whose fundus image has not been screened yet. */
export function isAwaitingScreening(c: CaseListItem): boolean {
  return c.status === 'created';
}

/** A case with a recorded human decision. */
export function isReviewed(c: CaseListItem): boolean {
  return c.status === 'reviewed';
}
