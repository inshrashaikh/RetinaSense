/**
 * HTTP client for the RetinaSense backend API.
 *
 * - Base URL: VITE_API_BASE_URL (default http://127.0.0.1:8000)
 * - Every request aborts after a timeout (timeoutMs).
 * - Errors are normalised into ApiError with a stable `code` and a `kind`
 *   (http | network | timeout | malformed) so the UI can show honest,
 *   human-friendly messages and never leak stack traces.
 *
 * This module is PRODUCTION/API mode only. The DEMO client lives in demo.ts.
 */

export const API_BASE_URL: string =
  (import.meta.env.VITE_API_BASE_URL as string | undefined) ?? 'http://127.0.0.1:8000';

export const DEFAULT_TIMEOUT_MS = 30_000;
export const SCREEN_TIMEOUT_MS = 90_000;

export interface ApiError {
  kind: 'http' | 'network' | 'timeout' | 'malformed';
  code: string;
  message: string;
  httpStatus?: number;
  stage?: string;
}

export function isApiError(e: unknown): e is ApiError {
  return typeof e === 'object' && e !== null && 'kind' in e && 'code' in e;
}

interface RequestOptions {
  method?: 'GET' | 'POST';
  body?: BodyInit;
  headers?: Record<string, string>;
  /** Do not set Content-Type manually for FormData — the browser adds the boundary. */
  timeoutMs?: number;
}

export async function apiRequest<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      method: opts.method ?? 'GET',
      headers: opts.headers,
      body: opts.body,
      signal: controller.signal,
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw makeError('timeout', 'TIMEOUT', `Request timed out after ${timeoutMs} ms.`);
    }
    throw makeError(
      'network',
      'NETWORK_ERROR',
      'Cannot reach the RetinaSense backend. Check that it is running and the API base URL is correct.',
    );
  } finally {
    clearTimeout(timer);
  }

  let data: unknown = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }

  if (!res.ok) {
    const errBody = (data as { error?: { code?: string; message?: string; stage?: string } } | null);
    throw makeError(
      'http',
      errBody?.error?.code ?? 'INTERNAL_ERROR',
      errBody?.error?.message ?? `Request failed with HTTP ${res.status}.`,
      res.status,
      errBody?.error?.stage,
    );
  }

  if (data === null) {
    throw makeError('malformed', 'BAD_RESPONSE', 'The backend returned an empty or invalid response.');
  }

  return data as T;
}

/** Like apiRequest but returns a raw Blob (used for image retrieval). */
export async function apiRequestBlob(path: string, opts: RequestOptions = {}): Promise<Blob> {
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      method: opts.method ?? 'GET',
      headers: opts.headers,
      signal: controller.signal,
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw makeError('timeout', 'TIMEOUT', `Request timed out after ${timeoutMs} ms.`);
    }
    throw makeError(
      'network',
      'NETWORK_ERROR',
      'Cannot reach the RetinaSense backend. Check that it is running and the API base URL is correct.',
    );
  } finally {
    clearTimeout(timer);
  }

  if (!res.ok) {
    let data: unknown = null;
    try {
      data = await res.json();
    } catch {
      data = null;
    }
    const errBody = (data as { error?: { code?: string; message?: string; stage?: string } } | null);
    throw makeError(
      'http',
      errBody?.error?.code ?? 'INTERNAL_ERROR',
      errBody?.error?.message ?? `Request failed with HTTP ${res.status}.`,
      res.status,
      errBody?.error?.stage,
    );
  }

  return res.blob();
}

function makeError(
  kind: ApiError['kind'],
  code: string,
  message: string,
  httpStatus?: number,
  stage?: string,
): ApiError {
  return { kind, code, message, httpStatus, stage };
}