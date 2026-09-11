/**
 * Image preview — fetched from the backend image endpoint
 * (GET /api/cases/{caseId}/image).  Honest about images the backend cannot
 * serve: it shows a message instead of inventing a picture.
 */
import { useEffect, useState } from 'react';
import { fetchCaseImage } from '../api/endpoints';
import { friendlyError } from '../utils/errors';

type ImageState = 'loading' | 'done' | 'unavailable';

export function ImagePreview({ caseId }: { caseId: string }) {
  const [state, setState] = useState<ImageState>('loading');
  const [src, setSrc] = useState<string | null>(null);
  const [detail, setDetail] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    let objectUrl: string | null = null;

    setState('loading');
    setDetail(null);
    fetchCaseImage(caseId)
      .then((blob) => {
        if (cancelled) return;
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
        setState('done');
      })
      .catch((err) => {
        if (cancelled) return;
        setDetail(friendlyError(err).detail);
        setState('unavailable');
      });

    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [caseId]);

  if (state === 'done' && src) {
    return <img className="fundus-img" src={src} alt={`Fundus image for case ${caseId}`} />;
  }

  if (state === 'unavailable') {
    return (
      <div className="image-placeholder" aria-label="Image preview unavailable">
        <p>
          <strong>Image preview unavailable</strong>
        </p>
        <p>{detail ?? 'The backend has no fundus image to serve for this case.'}</p>
      </div>
    );
  }

  return (
    <div className="image-placeholder" aria-label="Loading image preview">
      <p>
        <strong>Loading image…</strong>
      </p>
    </div>
  );
}