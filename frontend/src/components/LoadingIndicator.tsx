/**
 * Simple, static loading indicator (no animation) with a text label.
 */
export function LoadingIndicator({ label = 'Working…' }: { label?: string }) {
  return (
    <div className="loading" role="status" aria-live="polite">
      <span className="loading-spinner" aria-hidden="true" />
      <span>{label}</span>
    </div>
  );
}