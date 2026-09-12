/**
 * New screening — captures patient/eye metadata and a fundus image, runs the
 * quality gate + AI screening, then opens the case result page.
 *
 * Upload rules and validation behaviour are unchanged (JPEG/PNG, ≤20 MB —
 * mirroring the backend limits).
 */
import { useState } from 'react';
import { createCase, screenCase } from '../api/endpoints';
import { validateImageFile } from '../utils/validation';
import { friendlyError } from '../utils/errors';
import { Alert } from '../components/ui/Alert';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { FileDropzone } from '../components/ui/FileDropzone';
import { Field, Input, Select } from '../components/ui/Form';
import { LoadingState } from '../components/ui/Skeleton';
import { PageHeader } from '../components/ui/PageHeader';
import { navigate } from '../router';

type Step = 'idle' | 'creating' | 'screening' | 'error';
type InvalidField = 'patientId' | 'image' | null;

const EYES = [
  { value: 'OD', label: 'OD — right eye' },
  { value: 'OS', label: 'OS — left eye' },
];

export function NewScreeningPage() {
  const [patientId, setPatientId] = useState('');
  const [eye, setEye] = useState('OD');
  const [phcId, setPhcId] = useState('');
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [validationMsg, setValidationMsg] = useState('');
  const [invalidField, setInvalidField] = useState<InvalidField>(null);
  const [step, setStep] = useState<Step>('idle');
  const [caseId, setCaseId] = useState<string | null>(null);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);

  const busy = step === 'creating' || step === 'screening';

  function onFileSelect(f: File | null) {
    setFile(f);
    setValidationMsg('');
    setInvalidField(null);
    if (!f) {
      setPreview(null);
      return;
    }
    const v = validateImageFile(f);
    if (!v.ok) {
      setValidationMsg(v.message);
      setInvalidField('image');
      setPreview(null);
      return;
    }
    const reader = new FileReader();
    reader.onload = () => setPreview(typeof reader.result === 'string' ? reader.result : null);
    reader.readAsDataURL(f);
  }

  function resetImage() {
    setPreview(null);
    setFile(null);
    setValidationMsg('');
    setInvalidField(null);
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setValidationMsg('');
    setError(null);

    if (!patientId.trim()) {
      setValidationMsg('Please enter a patient id.');
      setInvalidField('patientId');
      return;
    }
    const v = validateImageFile(file);
    if (!v.ok) {
      setValidationMsg(v.message);
      setInvalidField('image');
      return;
    }
    setInvalidField(null);

    const meta = { patientId: patientId.trim(), eye, phcId: phcId.trim() };
    try {
      setStep('creating');
      const created = await createCase(meta);
      setCaseId(created.caseId);
      setStep('screening');
      await screenCase(created.caseId, file!, meta);
      navigate(`/case/${created.caseId}`);
    } catch (err) {
      const f = friendlyError(err);
      setError(f);
      setStep('error');
    }
  }

  async function onRetry() {
    setError(null);
    const meta = { patientId: patientId.trim(), eye, phcId: phcId.trim() };
    if (!caseId || !file) {
      setStep('idle');
      return;
    }
    try {
      setStep('screening');
      await screenCase(caseId, file, meta);
      navigate(`/case/${caseId}`);
    } catch (err) {
      const f = friendlyError(err);
      setError(f);
      setStep('error');
    }
  }

  return (
    <div className="page">
      <PageHeader
        eyebrow="Step 1 · new case"
        title="New screening"
        subtitle="Upload a clear fundus image. The backend enforces the upload limits
          (JPEG/PNG, ≤20 MB) — the checks here are the same limits, applied instantly
          so nothing is uploaded needlessly."
      />

      {error && <Alert variant="error" title={error.title}>{error.detail}</Alert>}

      <form className="form form--wide" aria-label="Screening form" onSubmit={onSubmit}>
        <Card>
          <CardHeader
            title="Patient & eye"
            subtitle="Opaque tokens only — no personally identifying information."
            icon="user"
            bordered
          />
          <CardBody>
            <Field label="Patient id" hint="Opaque patient token, no PII.">
              <Input
                type="text"
                value={patientId}
                onChange={(e) => {
                  setPatientId(e.target.value);
                  if (invalidField === 'patientId') setInvalidField(null);
                }}
                placeholder="Opaque patient token, no PII"
                autoComplete="off"
                disabled={busy}
                className={invalidField === 'patientId' ? 'input--invalid' : ''}
                aria-invalid={invalidField === 'patientId' || undefined}
              />
            </Field>

            <Field label="Eye">
              <Select
                value={eye}
                onChange={(e) => setEye(e.target.value)}
                disabled={busy}
              >
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
          </CardBody>
        </Card>

        <Card>
          <CardHeader
            title="Fundus image"
            subtitle="JPEG or PNG · up to 20 MB · one image per case."
            icon="camera"
            bordered
          />
          <CardBody>
            <FileDropzone
              id="fundus-file"
              label="Fundus image"
              hint="The backend accepts JPEG and PNG up to 20 MB."
              emptyTitle="Drag & drop a fundus image, or browse"
              emptyHint="JPEG or PNG, max 20 MB · click or drop a file here"
              file={file}
              onSelect={onFileSelect}
              invalid={invalidField === 'image'}
              disabled={busy}
            />

            {validationMsg && (
              <Alert variant="warning" title="Check the image">
                {validationMsg}
              </Alert>
            )}

            {preview && (
              <div className="preview-block">
                <span className="field__label">Preview</span>
                <img
                  className="fundus-img fundus-img-preview"
                  src={preview}
                  alt="Selected fundus image preview"
                />
              </div>
            )}

            {busy && (
              <LoadingState
                label={
                  step === 'creating'
                    ? 'Creating the case…'
                    : 'Screening in progress… this may take up to 90 s (quality gate → AI grading).'
                }
              />
            )}
          </CardBody>
        </Card>

        <div className="form__actions btn-row">
          <Button type="submit" variant="primary" size="lg" icon="scan" loading={busy}>
            {step === 'creating' ? 'Creating case…' : step === 'screening' ? 'Screening…' : 'Run screening'}
          </Button>
          {step === 'error' && caseId && (
            <Button icon="refresh" onClick={() => void onRetry()}>
              Retry screening
            </Button>
          )}
          <Button variant="ghost" onClick={resetImage} disabled={busy || (!file && !preview)}>
            Clear image
          </Button>
          <span className="note-text">
            Run screening registers the case, enforces the quality gate and produces the
            AI-assisted grade.
          </span>
        </div>
      </form>
    </div>
  );
}
