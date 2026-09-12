/**
 * Minimal hash-based router (#/path). Keeps the prototype dependency-free.
 *
 * Section anchors on the public landing page (#how-it-works, #features, …) are
 * not routes: anything that does not start with "/" resolves to the landing
 * page, which then scrolls the matching section into view.
 */
import { useEffect, useState } from 'react';

export function getHashPath(): string {
  const h = window.location.hash;
  if (!h || h === '#') return '/';
  const raw = h.replace(/^#/, '');
  if (!raw.startsWith('/')) return '/';
  return raw;
}

/** The in-page section anchor (e.g. "how-it-works"), or null for real routes. */
export function getSectionAnchor(): string | null {
  const h = window.location.hash;
  if (!h || h === '#') return null;
  const raw = h.replace(/^#/, '');
  if (!raw || raw.startsWith('/')) return null;
  return raw;
}

export function navigate(path: string): void {
  window.location.hash = `#${path}`;
}

export function useHashPath(): string {
  const [path, setPath] = useState<string>(getHashPath());
  useEffect(() => {
    const onChange = () => setPath(getHashPath());
    window.addEventListener('hashchange', onChange);
    return () => window.removeEventListener('hashchange', onChange);
  }, []);
  return path;
}

/** Parse '/case/<id>/upload' from a hash path. */
export function caseUploadFromPath(path: string): string | null {
  const m = path.match(/^\/case\/([^/]+)\/upload\/?$/);
  return m ? decodeURIComponent(m[1]) : null;
}

/** Parse '/case/<id>' from a hash path (not /upload). */
export function caseIdFromPath(path: string): string | null {
  const m = path.match(/^\/case\/([^/]+)\/?$/);
  return m ? decodeURIComponent(m[1]) : null;
}

/** Parse '/reports/<id>' from a hash path. */
export function reportIdFromPath(path: string): string | null {
  const m = path.match(/^\/reports\/([^/]+)\/?$/);
  return m ? decodeURIComponent(m[1]) : null;
}
