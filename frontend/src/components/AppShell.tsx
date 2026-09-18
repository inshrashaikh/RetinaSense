/**
 * AppShell — the internal application frame.
 *
 * Light, honeydew-tinted sidebar + sticky topbar, using the same design system
 * as the public landing page. The public landing page is NOT rendered inside
 * this shell (see App.tsx).
 */
import { useEffect, useState, type ReactNode } from 'react';
import { DemoModeBanner } from './DemoModeBanner';
import { DISCLAIMER } from './DisclaimerFooter';
import { BackendHealthChip } from './BackendHealthChip';
import { Button } from './ui/Button';
import { Icon, type IconName } from './ui/Icon';
import { navigate, useHashPath } from '../router';
import { clearSession, getUser, roleLabel, type Role } from '../auth/session';

interface NavItem {
  label: string;
  path: string;
  icon: IconName;
  match: (path: string) => boolean;
}

interface NavGroup {
  label: string;
  items: NavItem[];
}

const DASHBOARD_ITEM: NavItem = {
  label: 'Dashboard',
  path: '/dashboard',
  icon: 'grid',
  match: (p) => p === '/dashboard',
};

const SCREENING_ITEMS: NavItem[] = [
  DASHBOARD_ITEM,
  { label: 'New screening', path: '/screening', icon: 'plus', match: (p) => p === '/screening' },
  { label: 'Latest result', path: '/result', icon: 'activity', match: (p) => p === '/result' },
];

const CASES_ITEM: NavItem = {
  label: 'Cases',
  path: '/cases',
  icon: 'layers',
  match: (p) => p === '/cases' || p === '/cases/new' || p.startsWith('/case/'),
};

const REPORTS_ITEM: NavItem = {
  label: 'Reports',
  path: '/reports',
  icon: 'file',
  match: (p) => p === '/reports' || p.startsWith('/reports/'),
};

/**
 * Build the sidebar for a role. Operators capture and screen, but the review
 * queue is clinical-review work for ophthalmologists/admins. With no role
 * (DEMO mode or a session whose role is unknown) the review destination stays
 * visible — the backend still enforces the role on every request.
 */
function navGroupsFor(role: Role | undefined | null): NavGroup[] {
  const isOperator = role === 'phc_operator';
  const records: NavItem[] = [CASES_ITEM];

  if (!isOperator) {
    records.push({
      label: 'Review queue',
      path: '/review',
      icon: 'inbox',
      match: (p) => p === '/review',
    });
  }
  records.push(REPORTS_ITEM);

  return [
    { label: 'Screening', items: SCREENING_ITEMS },
    { label: isOperator ? 'Capture records' : 'Clinical work', items: records },
  ];
}

export function AppShell({ children, demoMode }: { children: ReactNode; demoMode: boolean }) {
  const [navOpen, setNavOpen] = useState(false);
  const path = useHashPath();
  const user = getUser();

  // Close the mobile drawer whenever the hash route changes.
  useEffect(() => {
    setNavOpen(false);
  }, [path]);

  const navGroups = navGroupsFor(user?.role);
  const activeItem = navGroups.flatMap((g) => g.items).find((i) => i.match(path));

  function signOut() {
    clearSession();
    navigate('/');
  }

  return (
    <div className={`shell${navOpen ? ' shell--nav-open' : ''}`}>
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>
      {demoMode && <DemoModeBanner />}

      <div className="shell__body">
        <button
          type="button"
          className="shell__scrim"
          aria-label="Dismiss navigation"
          tabIndex={navOpen ? 0 : -1}
          onClick={() => setNavOpen(false)}
        />

        <aside className="sidebar" id="app-sidebar" aria-label="Sidebar">
          <button type="button" className="sidebar__brand" onClick={() => navigate('/dashboard')}>
            <span className="brand-mark" aria-hidden="true">
              RS
            </span>
            <span className="brand-text">
              <strong>RetinaSense</strong>
              <span className="brand-tagline">DR screening decision-support</span>
            </span>
          </button>

          <nav className="sidebar__nav" aria-label="Application navigation">
            {navGroups.map((group) => (
              <div className="nav-group" key={group.label}>
                <span className="nav-group__label">{group.label}</span>
                {group.items.map((item) => {
                  const active = item.match(path);
                  return (
                    <a
                      key={item.path}
                      href={`#${item.path}`}
                      className={`nav-item${active ? ' nav-item--active' : ''}`}
                      aria-current={active ? 'page' : undefined}
                    >
                      <span className="nav-item__icon">
                        <Icon name={item.icon} size={18} />
                      </span>
                      {item.label}
                    </a>
                  );
                })}
              </div>
            ))}
          </nav>

          <div className="sidebar__footer">
            <BackendHealthChip />
            <Button variant="ghost" size="sm" icon="home" onClick={() => navigate('/')}>
              Public site
            </Button>
          </div>
        </aside>

        <div className="shell__main">
          <header className="topbar">
            <div className="topbar__left">
              <Button
                variant="ghost"
                icon={navOpen ? 'x' : 'menu'}
                className="topbar__menu"
                aria-label={navOpen ? 'Close navigation' : 'Open navigation'}
                aria-expanded={navOpen}
                aria-controls="app-sidebar"
                onClick={() => setNavOpen((v) => !v)}
              />
              <span className="topbar__title">{activeItem?.label ?? 'RetinaSense'}</span>
            </div>
            <div className="topbar__right">
              {user && (
                <div className="app-user">
                  <span className="app-user__identity">
                    <span className="app-user__name">{user.name || user.username}</span>
                    <span className="app-user__role">{roleLabel(user.role)}</span>
                  </span>
                  <Button
                    variant="ghost"
                    size="sm"
                    icon="x"
                    aria-label="Sign out"
                    onClick={signOut}
                  >
                    Sign out
                  </Button>
                </div>
              )}
              {/* The CTA is redundant while the screening form itself is open. */}
              {path !== '/screening' && (
                <Button
                  variant="primary"
                  size="sm"
                  icon="plus"
                  onClick={() => navigate('/screening')}
                >
                  New screening
                </Button>
              )}
            </div>
          </header>

          <main className="shell__content" id="main-content">
            {children}
          </main>

          <footer className="app-footer" role="note">
            <div className="app-footer__inner">
              <span>RetinaSense · AI-assisted DR screening (prototype)</span>
              <span>{DISCLAIMER}</span>
            </div>
          </footer>
        </div>
      </div>
    </div>
  );
}
