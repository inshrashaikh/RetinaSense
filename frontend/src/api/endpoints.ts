/**
 * Endpoint functions used by the UI.
 *
 * The app talks to the real backend by default (production/API mode). When
 * VITE_DEMO_MODE=true, these functions delegate to the clearly-labelled DEMO
 * client (demo.ts). Demo output is never presented as a real screening: the
 * UI renders a persistent "DEMO MODE" banner whenever the flag is on.
 */
import { apiRequest, apiRequestBlob, SCREEN_TIMEOUT_MS } from './client';
import * as demo from './demo';
import type {
  CaseListItem,
  CaseResponse,
  CaseStats,
  CreateCaseRequest,
  CreateCaseResponse,
  HealthResponse,
  ReportResponse,
  ReviewRequest,
  ReviewResponse,
} from './types';

/**
 * True when the frontend is running against the DEMO (simulated) client.
 * Never enabled in production builds (VITE_DEMO_MODE must be set explicitly).
 */
export const isDemoMode: boolean = import.meta.env.VITE_DEMO_MODE === 'true';

function formFromMeta(meta: CreateCaseRequest): FormData {
  const fd = new FormData();
  if (meta.patientId) fd.set('patientId', meta.patientId);
  if (meta.eye) fd.set('eye', meta.eye);
  if (meta.phcId) fd.set('phcId', meta.phcId);
  return fd;
}

export async function createCase(meta: CreateCaseRequest = {}): Promise<CreateCaseResponse> {
  if (isDemoMode) return demo.createCase(meta);
  return apiRequest<CreateCaseResponse>('/api/cases', {
    method: 'POST',
    body: formFromMeta(meta),
    timeoutMs: 15_000,
  });
}

export async function screenCase(
  caseId: string,
  file: File,
  meta: CreateCaseRequest = {},
): Promise<CaseResponse> {
  if (isDemoMode) return demo.screenCase(caseId, file, meta);
  const fd = formFromMeta(meta);
  fd.set('image', file);
  return apiRequest<CaseResponse>(`/api/cases/${encodeURIComponent(caseId)}/screen`, {
    method: 'POST',
    body: fd,
    timeoutMs: SCREEN_TIMEOUT_MS,
  });
}

export async function getCase(caseId: string): Promise<CaseResponse> {
  if (isDemoMode) return demo.getCase(caseId);
  return apiRequest<CaseResponse>(`/api/cases/${encodeURIComponent(caseId)}`, {
    timeoutMs: 15_000,
  });
}

export async function listCases(): Promise<CaseListItem[]> {
  if (isDemoMode) return demo.listCases();
  return apiRequest<CaseListItem[]>('/api/cases', { timeoutMs: 15_000 });
}

export async function fetchCaseImage(caseId: string): Promise<Blob> {
  if (isDemoMode) return demo.fetchCaseImage(caseId);
  return apiRequestBlob(`/api/cases/${encodeURIComponent(caseId)}/image`, {
    timeoutMs: 15_000,
  });
}

export async function submitReview(
  caseId: string,
  review: ReviewRequest,
): Promise<ReviewResponse> {
  if (isDemoMode) return demo.submitReview(caseId, review);
  return apiRequest<ReviewResponse>(`/api/cases/${encodeURIComponent(caseId)}/review`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(review),
    timeoutMs: 15_000,
  });
}

export async function fetchReport(caseId: string): Promise<ReportResponse> {
  if (isDemoMode) return demo.fetchReport(caseId);
  return apiRequest<ReportResponse>(`/api/cases/${encodeURIComponent(caseId)}/report`, {
    timeoutMs: 15_000,
  });
}

export async function fetchHealth(): Promise<HealthResponse> {
  if (isDemoMode) return demo.fetchHealth();
  return apiRequest<HealthResponse>('/api/health', { timeoutMs: 10_000 });
}

export async function fetchCaseStats(): Promise<CaseStats> {
  if (isDemoMode) return demo.fetchCaseStats();
  return apiRequest<CaseStats>('/api/cases/stats', { timeoutMs: 10_000 });
}

export async function generateReport(caseId: string): Promise<ReportResponse> {
  if (isDemoMode) return demo.generateReport(caseId);
  return apiRequest<ReportResponse>(`/api/cases/${encodeURIComponent(caseId)}/report`, {
    method: 'POST',
    timeoutMs: 15_000,
  });
}