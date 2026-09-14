/**
 * Upload flow — attaches a fundus image to an existing case and runs the
 * screening. The same client-side guard as the combined form applies, and the
 * backend remains the authoritative validator.
 */
import { useState } from 'react';
import { screenCase } from '../api/endpoints';
import { validateImageFile } from '../utils/validation';
import { friendlyError } from '../utils/errors';
import { Alert } from '../components/ui/Alert';
import { Badge } from '../components/ui/Badge';
import { Breadcrumbs } from '../components/ui/Breadcrumbs';
import { Button } from '../components/ui/Button';
import { Card, CardBody, CardHeader } from '../components/ui/Card';
import { FileDropzone } from '../components/ui/FileDropzone';
import { PageHeader } from '../components/ui/PageHeader';
import { LoadingState } from '../components/ui/Skeleton';
import { navigate } from '../router';

export function CaseUploadPage({ caseId }: { caseId: string }) {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [validationMsg, setValidationMsg] = useState('');
  const [invalid, setInvalid] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ title: string; detail: string } | null>(null);

  function onFileSelect(f: File | null) {
    setFile(f);
    setValidationMsg('');
    setInvalid(false);
    if (!f) {
      setPreview(null);
      return;
    }
    const v = validateImageFile(f);
    if (!v.ok) {
      setValidationMsg(v.message);
      setInvalid(true);
      setPreview(null);
      return;
    }
    const reader = new FileReader();
    reader.onload = () => setPreview(typeof reader.result === 'string' ? reader.result : null);
    reader.readAsDataURL(f);
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setValidationMsg('');
    setError(null);

    const v = validateImageFile(file);
    if (!v.ok) {
      setValidationMsg(v.message);
      setInvalid(true);
      return;
    }

    setBusy(true);
    try {
      await screenCase(caseId, file!);
      navigate(`/case/${caseId}`);
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  }

  return (
    <div className="page">
      <Breadcrumbs
        items={[
          { label: 'Cases', path: '/cases' },
          { label: caseId, path: `/case/${caseId}` },
          { label: 'Upload image' },
        ]}
      />

      <PageHeader
        eyebrow="Step 2 · upload"
        title="Upload fundus image"
        subtitle="The case is registered with the case id below. Attaching the image runs
          the quality gate and AI-assisted grading, then opens the result."
        badges={<Badge tone="neutral" icon="layers">{caseId}</Badge>}
      />

      {error && <Alert variant="error" title={error.title}>{error.detail}</Alert>}

      <form className="form" aria-label="Upload fundus image form" onSubmit={onSubmit}>
        <Card>
          <CardHeader
            title="Fundus image"
            subtitle="JPEG or PNG · up to 20 MB."
            icon="camera"
            bordered
          />
          <CardBody>
            <FileDropzone
              id="upload-fundus-file"
              label="Fundus image"
              hint="One image per case. Re-uploading replaces the stored image on the backend."
              emptyTitle="Drag & drop a fundus image, or browse"
              file={file}
              onSelect={onFileSelect}
              invalid={invalid}
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
              <LoadingState label="Screening in progress… this may take up to 90 s (quality gate → AI grading)." />
            )}

            <div className="btn-row">
              <Button type="submit" variant="primary" size="lg" icon="scan" loading={busy}>
                {busy ? 'Screening…' : 'Run screening'}
              </Button>
              <Button variant="ghost" onClick={() => navigate(`/case/${caseId}`)} disabled={busy}>
                Open case without screening
              </Button>
            </div>
          </CardBody>
        </Card>
      </form>
    </div>
  );
}
