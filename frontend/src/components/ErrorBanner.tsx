/**
 * Error banner — a thin, honest wrapper over the Alert primitive so every
 * failure state in the app looks and announces the same way.
 */
import { Alert } from './ui/Alert';

export function ErrorBanner({ title, detail }: { title: string; detail: string }) {
  return (
    <Alert variant="error" title={title}>
      {detail}
    </Alert>
  );
}
