/**
 * Minimal hash-based router (#/path). Keeps the prototype dependency-free.
 */
import { useEffect, useState } from 'react';

export function getHashPath(): string {
  const h = window.location.hash;
  if (!h || h === '#') return '/';
  return h.replace(/^#/, '');
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

/** Parse '/case/<id>' from a hash path. */
export function caseIdFromPath(path: string): string | null {
  const m = path.match(/^\/case\/([^/]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}

/** Parse '/reports/<id>' from a hash path. */
export function reportIdFromPath(path: string): string | null {
  const m = path.match(/^\/reports\/([^/]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}