/**
 * Client-side auth session — bearer token + user profile in localStorage.
 *
 * The backend signs tokens with HMAC-SHA256 (backend/app/utils/security.py);
 * the frontend only stores and replays them. Every API call that needs
 * authentication attaches the token via `Authorization: Bearer <token>`
 * (see api/client.ts). This module is intentionally tiny and framework-free:
 * React re-renders by subscribing with `subscribeAuth` (used by App.tsx).
 */

export type Role = 'phc_operator' | 'ophthalmologist' | 'admin';

export interface UserInfo {
  id: number;
  username: string;
  name: string;
  role: Role;
}

const TOKEN_KEY = 'retinasense_token';
const USER_KEY = 'retinasense_user';

/** Human-readable role names used in navigation and the account chip. */
export const ROLE_LABELS: Record<Role, string> = {
  phc_operator: 'PHC operator',
  ophthalmologist: 'Ophthalmologist',
  admin: 'Administrator',
};

export function roleLabel(role: Role | undefined | null): string {
  if (!role) return 'Signed out';
  return ROLE_LABELS[role] ?? role;
}

export function getToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function getUser(): UserInfo | null {
  try {
    const raw = localStorage.getItem(USER_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return null;
    return parsed as UserInfo;
  } catch {
    return null;
  }
}

export function saveSession(token: string, user: UserInfo): void {
  try {
    localStorage.setItem(TOKEN_KEY, token);
    localStorage.setItem(USER_KEY, JSON.stringify(user));
  } catch {
    // Storage unavailable (e.g. privacy mode) — auth simply won't persist.
  }
  notifyAuthChange();
}

export function clearSession(): void {
  try {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  } catch {
    // Storage unavailable — nothing to clear.
  }
  notifyAuthChange();
}

export function isAuthenticated(): boolean {
  return !!getToken();
}

/** True when the active account may make final human review decisions. */
export function canReview(role: Role | undefined): boolean {
  return role === 'ophthalmologist' || role === 'admin';
}

type Listener = () => void;

const _listeners: Listener[] = [];

export function subscribeAuth(listener: Listener): () => void {
  _listeners.push(listener);
  return () => {
    const i = _listeners.indexOf(listener);
    if (i >= 0) _listeners.splice(i, 1);
  };
}

function notifyAuthChange(): void {
  for (const listener of _listeners) {
    try {
      listener();
    } catch {
      // A listener must never break the rest.
    }
  }
}