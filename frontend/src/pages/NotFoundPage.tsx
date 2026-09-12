/**
 * 404 — no route matched. Offers a way back rather than a dead end.
 */
import { EmptyState } from '../components/ui/EmptyState';
import { PageHeader } from '../components/ui/PageHeader';
import { Button } from '../components/ui/Button';
import { navigate } from '../router';

export function NotFoundPage({ path }: { path: string }) {
  return (
    <div className="page">
      <PageHeader
        title="Page not found"
        subtitle="The address you followed does not match any screen in RetinaSense."
      />
      <EmptyState
        icon="search"
        title="No route matches this address"
        action={
          <>
            <Button variant="primary" icon="grid" onClick={() => navigate('/dashboard')}>
              Go to dashboard
            </Button>
            <Button icon="home" onClick={() => navigate('/')}>
              Back to home
            </Button>
          </>
        }
      >
        <p>
          Requested path: <code>{path}</code>
        </p>
        <p className="note-text">
          Dynamic addresses for cases and reports look like <code>#/case/&lt;id&gt;</code>{' '}
          and <code>#/reports/&lt;id&gt;</code>.
        </p>
      </EmptyState>
    </div>
  );
}
