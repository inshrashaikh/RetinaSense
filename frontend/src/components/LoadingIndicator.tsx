/**
 * Loading indicator (kept as the shared entry point used by the pages).
 */
import { LoadingState } from './ui/Skeleton';

export function LoadingIndicator({ label = 'Working…' }: { label?: string }) {
  return <LoadingState label={label} />;
}
