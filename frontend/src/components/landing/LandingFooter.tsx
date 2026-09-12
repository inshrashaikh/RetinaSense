/**
 * LandingFooter — premium public footer with navigation and the mandatory
 * screening disclaimer.
 */
import { DisclaimerFooter } from '../DisclaimerFooter';
import { Icon } from '../ui/Icon';
import { navigate } from '../../router';

const PRODUCT_LINKS: { label: string; path: string }[] = [
  { label: 'Dashboard', path: '/dashboard' },
  { label: 'New screening', path: '/screening' },
  { label: 'Cases', path: '/cases' },
  { label: 'Review queue', path: '/review' },
  { label: 'Reports', path: '/reports' },
];

const SECTION_LINKS: { label: string; anchor: string }[] = [
  { label: 'How it works', anchor: '#how-it-works' },
  { label: 'Technology', anchor: '#technology' },
  { label: 'Features', anchor: '#features' },
  { label: 'Human in the loop', anchor: '#human-in-the-loop' },
  { label: 'Safety & trust', anchor: '#safety' },
];

export function LandingFooter() {
  const year = new Date().getFullYear();

  return (
    <footer className="l-footer">
      <div className="l-container">
        <div className="l-footer__grid">
          <div className="l-footer__brand">
            <a className="l-brand" href="#top" aria-label="Back to top">
              <span className="brand-mark" aria-hidden="true">
                RS
              </span>
              <span className="brand-text">
                <strong>RetinaSense</strong>
                <span className="brand-tagline">AI-assisted DR screening</span>
              </span>
            </a>
            <p className="l-footer__desc">
              A diabetic retinopathy screening console that pairs an image-quality gate
              and AI-assisted grading with an explicit, separate human review — so the
              final referral decision is always a clinician&apos;s.
            </p>
          </div>

          <div>
            <h2 className="l-footer__heading">Application</h2>
            <ul className="l-footer__links">
              {PRODUCT_LINKS.map((link) => (
                <li key={link.path}>
                  <button
                    type="button"
                    className="l-footer__link"
                    onClick={() => navigate(link.path)}
                  >
                    {link.label}
                  </button>
                </li>
              ))}
            </ul>
          </div>

          <div>
            <h2 className="l-footer__heading">Explore</h2>
            <ul className="l-footer__links">
              {SECTION_LINKS.map((link) => (
                <li key={link.anchor}>
                  <a className="l-footer__link" href={link.anchor}>
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="l-footer__bottom">
          <DisclaimerFooter />
          <div className="l-footer__legal">
            <span>
              <Icon name="info" size={14} /> RetinaSense · project prototype ·{' '}
              {year}
            </span>
            <span>Built as a research and demonstration system — not a medical device.</span>
          </div>
        </div>
      </div>
    </footer>
  );
}
