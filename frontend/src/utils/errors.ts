/**
 * Maps backend/network errors to concise, reviewable UI messages.
 * Never shows raw stack traces or filesystem paths.
 */
import { isApiError } from '../api/client';

export interface FriendlyError {
  title: string;
  detail: string;
}

const CODE_MESSAGES: Record<string, FriendlyError> = {
  INVALID_IMAGE: {
    title: 'Invalid image',
    detail: 'The uploaded file could not be read as a valid image. Please upload a clear JPEG or PNG fundus photo.',
  },
  UNSUPPORTED_FILE_TYPE: {
    title: 'Unsupported file type',
    detail: 'Only JPEG and PNG fundus images are accepted.',
  },
  IMAGE_TOO_LARGE: {
    title: 'Image too large',
    detail: 'The image exceeds the 20 MB upload limit. Please upload a smaller fundus photo.',
  },
  UNGRADABLE_IMAGE: {
    title: 'Image ungradable',
    detail: 'The backend could not grade this image. Recapture instructions are shown on the result page.',
  },
  MODEL_UNAVAILABLE: {
    title: 'Screening engine unavailable',
    detail: 'The DR model is not available on the backend. No prediction was produced — no result is shown.',
  },
  MATLAB_ENGINE_UNAVAILABLE: {
    title: 'Screening engine unavailable',
    detail: 'Screening engine unavailable — MATLAB connection required. No result was fabricated.',
  },
  CASE_NOT_FOUND: {
    title: 'Case not found',
    detail: 'No case exists with this ID on the backend.',
  },
  INVALID_REVIEW: {
    title: 'Invalid review',
    detail: 'The review could not be submitted. Please check the action and grade and try again.',
  },
  REPORT_UNAVAILABLE: {
    title: 'Report not available',
    detail: 'A report has not been generated for this case yet. Reports are produced by the pipeline after a completed screening.',
  },
  IMAGE_UNAVAILABLE: {
    title: 'Image not available',
    detail: 'No fundus image is stored for this case on the backend.',
  },
  ARTIFACT_UNAVAILABLE: {
    title: 'Explainability image not available',
    detail: 'The backend has no Grad-CAM or evidence overlay stored for this case. Nothing is fabricated.',
  },
  INTERNAL_ERROR: {
    title: 'Backend error',
    detail: 'The backend reported an internal error. Please try again.',
  },
  TIMEOUT: {
    title: 'Request timed out',
    detail: 'The backend did not respond in time. Please check the network and try again.',
  },
  NETWORK_ERROR: {
    title: 'Backend unreachable',
    detail: 'Cannot reach the RetinaSense backend. Please check that it is running and the API base URL is correct.',
  },
  BAD_RESPONSE: {
    title: 'Unexpected response',
    detail: 'The backend returned a response the application could not read. No medical result is assumed.',
  },
};

export function friendlyError(e: unknown): FriendlyError {
  if (isApiError(e)) {
    return (
      CODE_MESSAGES[e.code] ?? {
        title: 'Request failed',
        detail: e.message,
      }
    );
  }
  if (e instanceof Error) {
    return { title: 'Unexpected error', detail: e.message };
  }
  return { title: 'Unexpected error', detail: 'An unexpected error occurred.' };
}

export function isEngineUnavailable(e: unknown): boolean {
  return isApiError(e) && (e.code === 'MODEL_UNAVAILABLE' || e.code === 'MATLAB_ENGINE_UNAVAILABLE');
}

export function isRecaptureError(e: unknown): boolean {
  return isApiError(e) && e.code === 'UNGRADABLE_IMAGE';
}