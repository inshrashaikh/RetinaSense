/**
 * Create case — registers a case and its metadata, then hands over to the
 * upload step. Useful when the image is captured separately from registration.
 */
import { useState } from 'react';
import { createCase } from '../api/endpoints';
import { friendlyError } from '../utils/errors';
import { Alert } from '../components/ui/Alert';
import { Breadcrumbs } from '../components/ui/Breadcrumbs';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { Field, Input, Select } from '../components/ui/Form';
import { PageHeader } from '../components/ui/PageHeader';
import { navigate } from '../router';

const EYES = [
  { value: 'OD', label: 'OD — right eye' },
  { value: 'OS', label: 'OS — left eye' },
];

export function CreateCasePage() {
  const [patientId, setPatientId] = useState('');
  const [eye, setEye] = useState('OD');
  const [phcId, setPhcId] = useState('');
  const [validationMsg, setValidationMsg] = useState('');
  const [invalid, setInvalid] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setValidationMsg('');
    setError(null);

    if (!patientId.trim()) {
      setValidationMsg('Please enter a patient id.');
      setInvalid(true);
      return;
    }
    setInvalid(false);

    setBusy(true);
    try {
      const created = await createCase({ patientId: patientId.trim(), eye, phcId: phcId.trim() });
      navigate(`/case/${created.caseId}/upload`);
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  }

  return (
    <div className="page">
      <Breadcrumbs items={[{ label: 'Cases', path: '/cases' }, { label: 'New case' }]} />

      <PageHeader
        eyebrow="Case registration"
        title="Create case"
        subtitle="Register the patient token, eye and PHC first. The fundus image is
          attached in the next step, and the screening runs only once an image is present."
        actions={
          <Button variant="ghost" icon="plus" onClick={() => navigate('/screening')}>
            Use the combined screening form
          </Button>
        }
      />

      {error && <Alert variant="error" title={error.title}>{error.detail}</Alert>}

      <form className="form" aria-label="Create case form" onSubmit={onSubmit}>
        <Card>
          <CardHeader
            title="Case details"
            subtitle="Metadata is stored with the case on the backend."
            icon="clipboard"
            bordered
          />
          <CardBody>
            <Field label="Patient id" hint="Opaque patient token, no PII.">
              <Input
                type="text"
                value={patientId}
                onChange={(e) => {
                  setPatientId(e.target.value);
                  if (invalid) setInvalid(false);
                }}
                placeholder="e.g. PT-1004"
                autoComplete="off"
                disabled={busy}
                className={invalid ? 'input--invalid' : ''}
                aria-invalid={invalid || undefined}
              />
            </Field>

            <Field label="Eye">
              <Select value={eye} onChange={(e) => setEye(e.target.value)} disabled={busy}>
                {EYES.map((o) => (
                  <option key={o.value} value={o.value}>{o.label}</option>
                ))}
              </Select>
            </Field>

            <Field label="PHC id">
              <Input
                type="text"
                value={phcId}
                onChange={(e) => setPhcId(e.target.value)}
                placeholder="Primary health centre id (optional)"
                autoComplete="off"
                disabled={busy}
              />
            </Field>

            {validationMsg && (
              <Alert variant="warning" title="Check the details">
                {validationMsg}
              </Alert>
            )}

            <div className="btn-row">
              <Button type="submit" variant="primary" size="lg" icon="plus" loading={busy}>
                {busy ? 'Creating case…' : 'Create case & continue'}
              </Button>
              <Button variant="ghost" onClick={() => navigate('/cases')} disabled={busy}>
                Cancel
              </Button>
            </div>
          </CardBody>
        </Card>
      </form>
    </div>
  );
}
