/**
 * ErrorBoundary — a render-time crash in one part of the UI must never blank
 * the whole application. Any uncaught error while rendering children is caught
 * here and replaced with a small, honest fallback plus a retry, instead of an
 * empty white screen.
 *
 * It does NOT catch event handlers / async errors (those are handled with
 * friendly errors at the call site); it exists purely for render crashes.
 */
import { Component, type ErrorInfo, type ReactNode } from 'react';
import { Button } from './ui/Button';

interface Props {
  children: ReactNode;
  /** Optional label used by tests / nesting. */
  label?: string;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('RetinaSense UI render error:', error, info.componentStack);
  }

  private reset = (): void => {
    this.setState({ error: null });
  };

  render(): ReactNode {
    const { error } = this.state;
    if (error) {
      return (
        <div className="page" role="alert" aria-live="assertive">
          <div className="error-boundary">
            <span className="badge badge--bad" aria-hidden="true">
              UI error
            </span>
            <h2>Something went wrong in the interface</h2>
            <p className="note-text">
              A rendering problem prevented this part of the app from drawing. Your
              screening data is stored on the backend and is not affected.
            </p>
            <div className="btn-row">
              <Button variant="primary" icon="refresh" onClick={this.reset}>
                Try again
              </Button>
              <Button icon="grid" onClick={() => { window.location.hash = '#/dashboard'; this.reset(); }}>
                Go to dashboard
              </Button>
            </div>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}