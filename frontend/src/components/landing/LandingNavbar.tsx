/**
 * LandingNavbar — public-site navigation.
 *
 * Section links are real `#anchor` links (shareable, keyboard accessible); the
 * hash router resolves non-route anchors back to the landing page.
 */
import { useState } from 'react';
import { Button } from '../ui/Button';
import { Icon } from '../ui/Icon';
import { navigate } from '../../router';
import { useActiveSection } from './useActiveSection';

interface SectionLink {
  id: string;
  label: string;
}

const SECTION_LINKS: SectionLink[] = [
  { id: 'top', label: 'Home' },
  { id: 'how-it-works', label: 'How it works' },
  { id: 'technology', label: 'Technology' },
  { id: 'features', label: 'Features' },
  { id: 'safety', label: 'Safety' },
];

export function LandingNavbar() {
  const [open, setOpen] = useState(false);
  const active = useActiveSection(SECTION_LINKS.map((s) => s.id));

  return (
    <header className={`l-nav${open ? ' l-nav--open' : ''}`}>
      <div className="l-container">
        <div className="l-nav__inner">
          <a className="l-brand" href="#top" aria-label="RetinaSense home">
            <span className="brand-mark" aria-hidden="true">
              RS
            </span>
            <span className="brand-text">
              <strong>RetinaSense</strong>
              <span className="brand-tagline">AI-assisted DR screening</span>
            </span>
          </a>

          <nav className="l-nav__links" aria-label="Landing sections">
            {SECTION_LINKS.map((link) => (
              <a
                key={link.id}
                className={`l-nav__link${active === link.id ? ' l-nav__link--active' : ''}`}
                href={`#${link.id}`}
                aria-current={active === link.id ? 'true' : undefined}
              >
                {link.label}
              </a>
            ))}
          </nav>

          <div className="l-nav__cta">
            <Button variant="ghost" onClick={() => navigate('/dashboard')}>
              Dashboard
            </Button>
            <Button variant="primary" icon="plus" onClick={() => navigate('/screening')}>
              Start screening
            </Button>
          </div>

          <Button
            variant="ghost"
            icon={open ? 'x' : 'menu'}
            className="l-nav__toggle"
            aria-label={open ? 'Close navigation' : 'Open navigation'}
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
          />
        </div>

        {open && (
          <nav className="l-nav__mobile" aria-label="Landing sections (mobile)">
            {SECTION_LINKS.map((link) => (
              <a
                key={link.id}
                className={`l-nav__link${active === link.id ? ' l-nav__link--active' : ''}`}
                href={`#${link.id}`}
                onClick={() => setOpen(false)}
              >
                <Icon name="chevronRight" size={15} />
                {link.label}
              </a>
            ))}
            <div className="l-nav__mobile-cta">
              <Button variant="secondary" icon="grid" onClick={() => navigate('/dashboard')}>
                Open dashboard
              </Button>
              <Button variant="primary" icon="plus" onClick={() => navigate('/screening')}>
                Start screening
              </Button>
            </div>
          </nav>
        )}
      </div>
    </header>
  );
}
