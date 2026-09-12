/**
 * StatsSection — screening activity counts.
 *
 * Values come from GET /api/cases/stats. When the backend is unreachable the
 * section says so; no count is estimated, extrapolated or invented.
 */
import { useEffect, useState } from 'react';
import { fetchCaseStats } from '../../api/endpoints';
import type { CaseStats } from '../../api/types';
import { Alert } from '../ui/Alert';
import { Icon, type IconName } from '../ui/Icon';
import { SkeletonStatGrid } from '../ui/Skeleton';

type State = 'loading' | 'done' | 'unavailable';

const CARDS: { key: keyof CaseStats; label: string; icon: IconName }[] = [
  { key: 'totalCases', label: 'Total cases', icon: 'layers' },
  { key: 'screeningsCompleted', label: 'Screenings completed', icon: 'checkCircle' },
  { key: 'pendingReviews', label: 'Pending reviews', icon: 'inbox' },
  { key: 'reviewed', label: 'Reviewed cases', icon: 'userCheck' },
];

export function StatsSection() {
  const [state, setState] = useState<State>('loading');
  const [stats, setStats] = useState<CaseStats | null>(null);

  useEffect(() => {
    let alive = true;
    fetchCaseStats()
      .then((s) => {
        if (!alive) return;
        setStats(s);
        setState('done');
      })
      .catch(() => {
        if (alive) setState('unavailable');
      });
    return () => {
      alive = false;
    };
  }, []);

  return (
    <section className="l-section l-section--mint" aria-labelledby="stats-title">
      <div className="l-container">
        <div className="l-section__head">
          <span className="eyebrow">Live pipeline activity</span>
          <h2 className="l-section__title" id="stats-title">
            Screening volume, exactly as recorded
          </h2>
          <p className="l-section__lead">
            These counts are read directly from the backend case store. Nothing here
            is a projection, a marketing figure or a model-performance claim.
          </p>
        </div>

        {state === 'loading' && <SkeletonStatGrid count={4} />}

        {state === 'unavailable' && (
          <Alert variant="info" title="Live statistics unavailable" icon="info">
            The backend is not reachable right now, so no activity figures can be
            shown. Nothing is estimated in their place.
          </Alert>
        )}

        {state === 'done' && stats && (
          <div className="l-stats">
            {CARDS.map((card) => (
              <div className="l-stat" key={card.key}>
                <div className="l-stat__top">
                  <span className="l-stat__label">{card.label}</span>
                  <span className="l-stat__icon" aria-hidden="true">
                    <Icon name={card.icon} size={18} />
                  </span>
                </div>
                <span className="l-stat__value">{stats[card.key]}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
