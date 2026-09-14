/**
 * Loading primitives — a labelled spinner plus skeletons for data-driven
 * cards and tables so no section is ever blank while data is in flight.
 */
export function LoadingState({ label = 'Working…' }: { label?: string }) {
  return (
    <div className="loading" role="status" aria-live="polite">
      <span className="loading-spinner" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}

export function LoadingBlock({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="loading-block" role="status" aria-live="polite">
      <span className="skeleton skeleton--title" aria-hidden="true" />
      <span className="skeleton skeleton--text" aria-hidden="true" />
      <span className="skeleton skeleton--text skeleton--w70" aria-hidden="true" />
      <span className="sr-only">{label}</span>
    </div>
  );
}

export function SkeletonStatGrid({ count = 6 }: { count?: number }) {
  return (
    <div className="stat-grid" aria-hidden="true">
      {Array.from({ length: count }).map((_, i) => (
        <div className="stat-card stat-card--skeleton" key={i}>
          <span className="skeleton skeleton--card" />
        </div>
      ))}
    </div>
  );
}

export function SkeletonRows({ rows = 3 }: { rows?: number }) {
  return (
    <div className="card__body" aria-hidden="true">
      {Array.from({ length: rows }).map((_, i) => (
        <span className="skeleton skeleton--text" key={i} />
      ))}
    </div>
  );
}

/** Small inline placeholder used when a single value is still loading. */
export function SkeletonValue({ label }: { label: string }) {
  return (
    <span className="loading" role="status" aria-live="polite">
      <span className="loading-spinner" aria-hidden="true" />
      <span>{label}</span>
    </span>
  );
}
