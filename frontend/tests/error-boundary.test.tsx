/**
 * ErrorBoundary — a render crash in one subtree must never blank the whole
 * app. It shows a small honest fallback and the retry recovers the UI.
 * It catches render-time crashes only (async/event errors are handled at
 * their call sites with friendly errors).
 */
import { describe, expect, it, vi, afterEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ErrorBoundary } from '../src/components/ErrorBoundary';

function Bomb({ explode }: { explode: boolean }) {
  if (explode) throw new Error('boom');
  return <p>recovered content</p>;
}

function Harness({ explode }: { explode: boolean }) {
  return (
    <ErrorBoundary>
      <Bomb explode={explode} />
    </ErrorBoundary>
  );
}

// React logs the caught error through console.error; silence it in these tests
// so a passing crash-test is not drowned in noise.
const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});

afterEach(() => {
  consoleError.mockClear();
});

describe('ErrorBoundary', () => {
  it('shows the fallback instead of a blank screen when a child crashes', async () => {
    render(<Harness explode />);

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Something went wrong in the interface');
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Go to dashboard' })).toBeInTheDocument();
    expect(screen.queryByText('recovered content')).not.toBeInTheDocument();
  });

  it('recovers after "Try again" once the crashing child is fixed', async () => {
    const { rerender } = render(<Harness explode />);
    await screen.findByRole('alert');

    // The crash cause is fixed (e.g. a transient bad prop); the boundary reset
    // re-mounts children cleanly instead of staying wedged on the fallback.
    rerender(<Harness explode={false} />);
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));

    expect(screen.getByText('recovered content')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });
});