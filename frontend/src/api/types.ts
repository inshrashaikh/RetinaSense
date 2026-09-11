/**
 * RetinaSense API types.
 *
 * Mirrors the backend Pydantic models (backend/app/models/schemas.py) and the
 * MATLAB Case contract (core/newCase.m, docs/ARCHITECTURE.md §4).
 *
 * Every medical field is nullable: the frontend NEVER invents a value. The
 * backend is the only source of medical output.
 */

export type QualityClass = 'good' | 'borderline' | 'ungradable' | null;

export interface QualityResult {
  /** Serialized as "class" (Pydantic alias). */
  class?: QualityClass | string | null;
  score: number | null;
  failureReasons: string[];
  recaptureReason?: string | null;
  recaptureInstruction?: string | null;
}

export interface AiPrediction {
  grade: number | null;
  gradeLabel: string | null;
  referable: boolean | null;
  confidence: number | null;
  uncertainty: number | null;
  reviewRequired: boolean | null;
}

export interface Explainability {
  gradCamAvailable: boolean;
  gradCamPath: string | null;
  evidenceAvailable: boolean;
  evidencePath: string | null;
}

export type ReviewStatus =
  | 'approved'
  | 'overridden'
  | 'recapture'
  | 'auto'
  | 'reqReview'
  | string
  | null;

export interface HumanReview {
  action: 'approve' | 'override' | 'recapture' | string | null;
  reviewerId: string | null;
  overrideGrade: number | null;
  finalReferral: boolean | null;
  status: ReviewStatus;
  notes: string | null;
  timestamp?: string | null;
}

export interface FinalDecision {
  grade: number | null;
  gradeLabel: string | null;
  referral: boolean | null;
}

export interface CaseResponse {
  caseId: string;
  status: string; // 'created' | 'completed' | 'recapture_required'
  quality: QualityResult;
  aiPrediction: AiPrediction | null;
  explainability: Explainability;
  humanReview: HumanReview | null;
  finalDecision: FinalDecision | null;
}

export interface HealthResponse {
  status: string;
  matlabEngine: boolean;
  version: string;
  /** SQLite database health reported by the backend ("ok" | "unavailable"). */
  database?: string;
}

export interface CreateCaseRequest {
  patientId?: string;
  eye?: string;
  phcId?: string;
}

export interface CreateCaseResponse {
  caseId: string;
  status: string;
}

/** Compact case summary for the dashboard recent-cases list (GET /api/cases). */
export interface CaseListItem {
  caseId: string;
  status: string;
  patientId: string;
  eye: string;
  phcId: string;
  createdAt: string | null;
}

/** Aggregated counts used by the dashboard stat cards (GET /api/cases/stats). */
export interface CaseStats {
  totalCases: number;
  screeningsCompleted: number;
  pendingReviews: number;
  recaptureRequired: number;
  reviewed: number;
  created: number;
}

export interface ReviewRequest {
  action: 'approve' | 'override' | 'recapture';
  reviewerId: string;
  overrideGrade?: number | null;
  finalReferral?: boolean | null;
  notes?: string;
}

export interface ReviewResponse {
  caseId: string;
  review: HumanReview;
  finalDecision: FinalDecision | null;
}

export interface ReportResponse {
  caseId: string;
  report: Record<string, unknown> | null;
  summary: string | null;
  disclaimer: string | null;
}

/** Grade 0–4 human-readable labels (matches config GRADE_LABELS). */
export const GRADE_LABELS: Record<number, string> = {
  0: 'No DR',
  1: 'Mild NPDR',
  2: 'Moderate NPDR',
  3: 'Severe NPDR',
  4: 'Proliferative DR',
};

export function gradeLabel(grade: number | null): string | null {
  if (grade === null || grade === undefined) return null;
  return GRADE_LABELS[grade] ?? 'Unknown';
}