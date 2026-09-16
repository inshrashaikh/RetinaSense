/**
 * Login — authenticates against the backend and stores the signed bearer token.
 *
 * Rendered standalone (outside the AppShell), matching the public landing
 * page. On success it stores the session and navigates to the dashboard. A
 * failed login shows the backend's honest message; there is no fake session.
 */
import { useState, type FormEvent } from 'react';
import { login } from '../api/endpoints';
import { saveSession, type UserInfo } from '../auth/session';
import { Alert } from '../components/ui/Alert';
import { Badge } from '../components/ui/Badge';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { Field, Input } from '../components/ui/Form';
import { navigate } from '../router';
import { isApiError } from '../api/client';

export function LoginPage() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (loading) return;
    if (!username.trim() || !password) {
      setError('Enter your username and password.');
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const res = await login(username.trim(), password);
      saveSession(res.token, res.user as UserInfo);
      navigate('/dashboard');
    } catch (err) {
      setError(
        isApiError(err)
          ? err.message
          : 'Sign-in failed. Check that the backend is running and try again.',
      );
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <div className="login-card__brand">
          <span className="brand-mark" aria-hidden="true">
            RS
          </span>
          <span className="brand-text">
            <strong>RetinaSense</strong>
            <span className="brand-tagline">DR screening decision-support</span>
          </span>
        </div>

        <Card aria-label="Sign in">
          <CardHeader
            title="Sign in"
            subtitle="Authenticate to open the screening console"
            icon="lock"
            bordered
          />
          <CardBody>
            <form onSubmit={onSubmit} data-testid="login-form">
              {error && (
                <Alert variant="error" title="Sign-in failed">
                  {error}
                </Alert>
              )}

              <div className="page-stack">
                <Field label="Username">
                  <Input
                    type="text"
                    name="username"
                    autoComplete="username"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    placeholder="e.g. doctor"
                    disabled={loading}
                    required
                  />
                </Field>
                <Field label="Password">
                  <Input
                    type="password"
                    name="password"
                    autoComplete="current-password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="••••••••"
                    disabled={loading}
                    required
                  />
                </Field>

                <Button
                  type="submit"
                  variant="primary"
                  block
                  icon="arrowRight"
                  loading={loading}
                >
                  {loading ? 'Signing in…' : 'Sign in'}
                </Button>

                <p className="note-text">
                  The backend seeds demo accounts — <Badge tone="neutral">operator</Badge>,{' '}
                  <Badge tone="neutral">doctor</Badge> and <Badge tone="neutral">admin</Badge> —
                  whose passwords are the dev defaults in{' '}
                  <code className="mono">backend/app/config.py</code>. Every screening is{' '}
                  decision-support only; no clinical claim is implied by signing in.
                </p>
              </div>
            </form>
          </CardBody>
        </Card>

        <div className="btn-row login-card__back">
          <Button variant="ghost" icon="home" onClick={() => navigate('/')}>
            Back to the public site
          </Button>
        </div>
      </div>
    </div>
  );
}