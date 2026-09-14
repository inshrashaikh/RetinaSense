/**
 * LandingPage — the public entry point at `#/`.
 *
 * Rendered outside the application shell: it has its own navbar and footer and
 * uses the same design system as the console so the identity carries through.
 */
import { useEffect } from 'react';
import { CtaSection } from '../components/landing/CtaSection';
import { FeaturesSection } from '../components/landing/FeaturesSection';
import { HeroSection } from '../components/landing/HeroSection';
import { HumanLoopSection } from '../components/landing/HumanLoopSection';
import { LandingFooter } from '../components/landing/LandingFooter';
import { LandingNavbar } from '../components/landing/LandingNavbar';
import { SafetySection } from '../components/landing/SafetySection';
import { StatsSection } from '../components/landing/StatsSection';
import { TechnologySection } from '../components/landing/TechnologySection';
import { WorkflowSection } from '../components/landing/WorkflowSection';
import { DemoModeBanner } from '../components/DemoModeBanner';

export function LandingPage({ demoMode }: { demoMode: boolean }) {
  useSectionAnchorScroll();

  return (
    <div className="landing">
      {demoMode && <DemoModeBanner />}
      <LandingNavbar />
      <main>
        <HeroSection />
        <StatsSection />
        <WorkflowSection />
        <TechnologySection />
        <FeaturesSection />
        <HumanLoopSection />
        <SafetySection />
        <CtaSection />
      </main>
      <LandingFooter />
    </div>
  );
}

/**
 * Section links (#how-it-works, …) are not routes. When one is used, scroll the
 * matching element into view — respecting `prefers-reduced-motion`.
 */
function useSectionAnchorScroll(): void {
  useEffect(() => {
    const scrollToAnchor = () => {
      const raw = window.location.hash.replace(/^#/, '');
      if (!raw || raw.startsWith('/')) return;
      const el = document.getElementById(raw);
      if (!el) return;
      const reduce =
        typeof window.matchMedia === 'function' &&
        window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      el.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
    };

    scrollToAnchor();
    window.addEventListener('hashchange', scrollToAnchor);
    return () => window.removeEventListener('hashchange', scrollToAnchor);
  }, []);
}
