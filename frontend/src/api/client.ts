/**
 * HTTP client for the RetinaSense backend API.
 *
 * - Base URL: VITE_API_BASE_URL. In the dev setup this is left EMPTY so the
 *   browser calls '/api/...' same-origin (localhost:5173) and the Vite dev
 *   server proxies to the backend (vite.config.ts) — no CORS or host
 *   mismatches. When unset it defaults to http://127.0.0.1:8000.
 * - Every request aborts after a timeout (timeoutMs).
 * - Errors are normalised into ApiError with a stable `code` and a `kind`
 *   (http | network | timeout | malformed) so the UI can show honest,
 *   human-friendly messages and never leak stack traces.
 *
 * This module is PRODUCTION/API mode only. The DEMO client lives in demo.ts.
 */

import { clearSession, getToken } from '../auth/session';

export const API_BASE_URL: string =
  (import.meta.env.VITE_API_BASE_URL as string | undefined)?.trim() || '';

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

/** Merge an `Authorization: Bearer <token>` header when a session exists. */
function withAuthHeaders(headers?: Record<string, string>): Record<string, string> {
  const merged: Record<string, string> = { ...headers };
  const token = getToken();
  if (token) merged['Authorization'] = `Bearer ${token}`;
  return merged;
}

/**
 * A 401 while authenticated means the session is invalid or expired: clear it
 * and bounce to the login screen, surfacing an honest error. A 401 on the
 * login endpoint itself is just a credentials mismatch — there is no session
 * to clear and the caller shows the backend's message.
 */
function handleUnauthorized(path: string, status: number, hasBody: Record<string, string> | null): ApiError {
  if (!path.startsWith('/api/auth/login')) {
    clearSession();
    if (window.location.hash) {
      window.location.hash = '#/login';
    }
  }
  const message =
    hasBody?.message ?? (path.startsWith('/api/auth/login')
      ? 'Invalid username or password. Please check your credentials and try again.'
      : 'Your session has expired. Please log in again.');
  return makeError('http', 'UNAUTHORIZED', message, status, hasBody?.stage ?? 'auth');
}

export async function apiRequest<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let res: Response;
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      method: opts.method ?? 'GET',
      headers: withAuthHeaders(opts.headers),
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
      `Cannot reach the RetinaSense backend (${describeFetchFailure(err)}). ` +
        'Please check that it is running and the API base URL is correct.',
    );
  } finally {
    clearTimeout(timer);
  }

  if (res.status === 401) {
    let body: Record<string, string> | null = null;
    try {
      const parsed = (await res.json()) as { error?: Record<string, string> } | null;
      body = parsed?.error ?? null;
    } catch {
      body = null;
    }
    throw handleUnauthorized(path, res.status, body);
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
      headers: withAuthHeaders(opts.headers),
      signal: controller.signal,
    });
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw makeError('timeout', 'TIMEOUT', `Request timed out after ${timeoutMs} ms.`);
    }
    throw makeError(
      'network',
      'NETWORK_ERROR',
      `Cannot reach the RetinaSense backend (${describeFetchFailure(err)}). ` +
        'Please check that it is running and the API base URL is correct.',
    );
  } finally {
    clearTimeout(timer);
  }

  if (!res.ok) {
    let parsed: unknown = null;
    try {
      parsed = await res.json();
    } catch {
      parsed = null;
    }

    if (res.status === 401) {
      const body = (parsed as { error?: Record<string, string> } | null)?.error ?? null;
      throw handleUnauthorized(path, res.status, body);
    }

    const errBody = (parsed as { error?: { code?: string; message?: string; stage?: string } } | null);
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

/**
 * Human-readable reason for a fetch() rejection. `fetch` only throws for
 * connection-level problems (refused, DNS, blocked, aborted by the network) —
 * and a CORS failure surfaces here too as "Failed to fetch", so surfacing the
 * cause helps distinguish "backend down" from "cross-origin blocked".
 */
function describeFetchFailure(err: unknown): string {
  if (err instanceof Error && err.message && err.message !== 'Failed to fetch') {
    return err.message;
  }
  return 'fetch failed (connection refused, blocked, or backend not running)';
}