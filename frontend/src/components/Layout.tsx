/**
 * App shell: header + navigation + footer disclaimer.
 */
import type { ReactNode } from 'react';
import { DemoModeBanner } from './DemoModeBanner';
import { DisclaimerFooter } from './DisclaimerFooter';
import { navigate, useHashPath } from '../router';

const NAV_ITEMS: { label: string; path: string; match: (path: string) => boolean }[] = [
  { label: 'Dashboard', path: '/', match: (p) => p === '/' },
  { label: 'New screening', path: '/screening', match: (p) => p === '/screening' },
  { label: 'Cases', path: '/cases', match: (p) => p === '/cases' },
  { label: 'Screening result', path: '/result', match: (p) => p === '/result' },
  { label: 'Review', path: '/review', match: (p) => p === '/review' },
  { label: 'Reports', path: '/reports' as string, match: (p) => p === '/reports' || p.startsWith('/reports/') },
];

export function Layout({ children, demoMode }: { children: ReactNode; demoMode: boolean }) {
  const path = useHashPath();

  return (
    <div className="app">
      {demoMode && <DemoModeBanner />}
      <header className="app-header">
        <div className="brand" onClick={() => navigate('/')} role="link" tabIndex={0}
          onKeyDown={(e) => { if (e.key === 'Enter') navigate('/'); }}>
          <span className="brand-mark" aria-hidden="true">RS</span>
          <span className="brand-text">
            <strong>RetinaSense</strong>
            <span className="brand-tagline">AI-assisted · human-in-the-loop DR screening</span>
          </span>
        </div>
        <nav className="nav" aria-label="Primary">
          {NAV_ITEMS.map((item) => (
            <button
              key={item.path === '/' ? 'dashboard' : item.path}
              type="button"
              className={`nav-link${item.match(path) ? ' nav-link-active' : ''}`}
              onClick={() => navigate(item.path)}
            >
              {item.label}
            </button>
          ))}
        </nav>
      </header>
      <main className="app-main">{children}</main>
      <DisclaimerFooter />
    </div>
  );
}