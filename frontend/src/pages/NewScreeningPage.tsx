/**
 * New screening — captures patient/eye metadata, a fundus image, runs the
 * quality gate + AI screening, and opens the case result page.
 */
import { useRef, useState } from 'react';
import { createCase, screenCase } from '../api/endpoints';
import { validateImageFile } from '../utils/validation';
import { friendlyError } from '../utils/errors';
import { ErrorBanner } from '../components/ErrorBanner';
import { LoadingIndicator } from '../components/LoadingIndicator';
import { navigate } from '../router';

type Step = 'idle' | 'creating' | 'screening' | 'error';

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
  const [step, setStep] = useState<Step>('idle');
  const [caseId, setCaseId] = useState<string | null>(null);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0] ?? null;
    setFile(f);
    setValidationMsg('');
    if (f) {
      const v = validateImageFile(f);
      if (!v.ok) {
        setValidationMsg(v.message);
        setPreview(null);
        return;
      }
      const reader = new FileReader();
      reader.onload = () => setPreview(typeof reader.result === 'string' ? reader.result : null);
      reader.readAsDataURL(f);
    } else {
      setPreview(null);
    }
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setValidationMsg('');
    setError(null);

    if (!patientId.trim()) {
      setValidationMsg('Please enter a patient id.');
      return;
    }
    const v = validateImageFile(file);
    if (!v.ok) {
      setValidationMsg(v.message);
      return;
    }

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
      <h1>New screening</h1>
      <p className="page-intro">
        Upload a clear fundus image. The backend enforces the upload limits
        (JPEG/PNG, ≤20 MB) — the checks here are the same, applied instantly.
      </p>

      {step === 'screening' && (
        <LoadingIndicator label="Screening in progress… this may take up to 90 s (quality gate → AI grading)." />
      )}

      {error && <ErrorBanner title={error.title} detail={error.detail} />}

      <form className="form" aria-label="Screening form" onSubmit={onSubmit}>
        <label className="field">
          <span className="field-label">Patient id</span>
          <input type="text" value={patientId} onChange={(e) => setPatientId(e.target.value)}
            placeholder="Opaque patient token, no PII" autoComplete="off" />
        </label>

        <label className="field">
          <span className="field-label">Eye</span>
          <select value={eye} onChange={(e) => setEye(e.target.value)}>
            {EYES.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </label>

        <label className="field">
          <span className="field-label">PHC id</span>
          <input type="text" value={phcId} onChange={(e) => setPhcId(e.target.value)}
            placeholder="Primary health centre id (optional)" autoComplete="off" />
        </label>

        <label className="field">
          <span className="field-label">Fundus image</span>
          <input
            ref={fileRef}
            type="file"
            accept="image/jpeg,image/png,.jpg,.jpeg,.png"
            onChange={onFileChange}
            aria-describedby="upload-hint"
          />
          <span id="upload-hint" className="hint">JPEG or PNG, max 20 MB.</span>
        </label>

        {validationMsg && (
          <div className="validation-error" role="alert">
            {validationMsg}
          </div>
        )}

        {preview && (
          <div className="preview-block">
            <span className="field-label">Preview</span>
            <img className="fundus-img fundus-img-preview" src={preview} alt="Selected fundus image preview" />
          </div>
        )}

        <div className="btn-row">
          <button type="submit" className="btn btn-primary btn-lg" disabled={step === 'creating' || step === 'screening'}>
            {step === 'creating' ? 'Creating case…' : step === 'screening' ? 'Screening…' : 'Run screening'}
          </button>
          {step === 'error' && caseId && (
            <button type="button" className="btn" onClick={onRetry}>Retry screening</button>
          )}
          <button
            type="button"
            className="btn"
            disabled={step === 'creating' || step === 'screening'}
            onClick={() => { setPreview(null); setFile(null); setValidationMsg(''); if (fileRef.current) fileRef.current.value = ''; }}
          >
            Clear
          </button>
        </div>
      </form>
    </div>
  );
}