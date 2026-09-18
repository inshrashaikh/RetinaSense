/**
 * useCaseBriefs — a bounded set of AI briefs for a doctor's worklist.
 *
 * The case-list endpoint is a compact summary, so a doctor's pending-review
 * worklist fetches each case to surface the AI grading alongside it. Fetches
 * are bounded (MAX_BRIEFS) and each failure is tracked individually: a brief
 * that cannot be read is reported as unavailable, never guessed.
 */
import { useEffect, useState } from 'react';
import { getCase } from '../api/endpoints';
import type { CaseResponse } from '../api/types';

/** Cap the per-case lookups so a large backlog never floods the backend. */
export const MAX_BRIEFS = 12;

export interface CaseBrief {
  caseId: string;
  grade: number | null;
  gradeLabel: string | null;
  referable: boolean | null;
  confidence: number | null;
  uncertainty: number | null;
  reviewRequired: boolean | null;
  gradCamAvailable: boolean;
}

export interface UseCaseBriefs {
  briefs: Record<string, CaseBrief>;
  /** Case ids whose brief could not be read from the backend. */
  failed: string[];
  loading: boolean;
}

function toBrief(caseId: string, c: CaseResponse): CaseBrief {
  return {
    caseId,
    grade: c.aiPrediction?.grade ?? null,
    gradeLabel: c.aiPrediction?.gradeLabel ?? null,
    referable: c.aiPrediction?.referable ?? null,
    confidence: c.aiPrediction?.confidence ?? null,
    uncertainty: c.aiPrediction?.uncertainty ?? null,
    reviewRequired: c.aiPrediction?.reviewRequired ?? null,
    gradCamAvailable: Boolean(c.explainability?.gradCamAvailable),
  };
}

export function useCaseBriefs(caseIds: string[]): UseCaseBriefs {
  const [briefs, setBriefs] = useState<Record<string, CaseBrief>>({});
  const [failed, setFailed] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);

  // A stable primitive key avoids re-fetching when the caller passes a new
  // array identity for the same ids.
  const key = caseIds.slice(0, MAX_BRIEFS).join('|');

  useEffect(() => {
    if (!key) {
      setBriefs({});
      setFailed([]);
      setLoading(false);
      return;
    }

    let alive = true;
    setLoading(true);
    const ids = key.split('|');

    Promise.all(
      ids.map(async (id) => {
        try {
          return { id, brief: toBrief(id, await getCase(id)) };
        } catch {
          return { id, brief: null };
        }
      }),
    ).then((results) => {
      if (!alive) return;
      const nextBriefs: Record<string, CaseBrief> = {};
      const nextFailed: string[] = [];
      for (const result of results) {
        if (result.brief) nextBriefs[result.id] = result.brief;
        else nextFailed.push(result.id);
      }
      setBriefs(nextBriefs);
      setFailed(nextFailed);
      setLoading(false);
    });

    return () => {
      alive = false;
    };
  }, [key]);

  return { briefs, failed, loading };
}
