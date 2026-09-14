/**
 * FileDropzone — the modern upload affordance used by the screening and upload
 * pages.
 *
 * The real `<input type="file">` covers the zone, so clicking, dropping and
 * keyboard operation all reach the same native control. Validation is injected
 * by the parent (which owns the `file` state and the guard), and clearing the
 * file resets the underlying input.
 */
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Icon } from './Icon';

interface Props {
  id: string;
  /** Visible label; also the accessible name of the file input. */
  label: ReactNode;
  hint?: ReactNode;
  emptyTitle?: ReactNode;
  emptyHint?: ReactNode;
  file: File | null;
  onSelect: (file: File | null) => void;
  invalid?: boolean;
  disabled?: boolean;
  accept?: string;
}

export function FileDropzone({
  id,
  label,
  hint,
  emptyTitle = 'Drag & drop an image, or browse',
  emptyHint = 'JPEG or PNG, max 20 MB',
  file,
  onSelect,
  invalid = false,
  disabled = false,
  accept = 'image/jpeg,image/png,.jpg,.jpeg,.png',
}: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [over, setOver] = useState(false);

  // A null file means "cleared": reset the native input so the same file can be
  // picked again without a page reload.
  useEffect(() => {
    if (!file && inputRef.current) inputRef.current.value = '';
  }, [file]);

  const labelId = `${id}-label`;
  const hintId = hint ? `${id}-hint` : undefined;

  return (
    <div className="field">
      <span className="field__label" id={labelId}>
        {label}
      </span>

      <label
        className={[
          'dropzone',
          over ? 'dropzone--over' : '',
          invalid ? 'dropzone--invalid' : '',
        ]
          .filter(Boolean)
          .join(' ')}
        htmlFor={id}
        onDragOver={(e) => {
          e.preventDefault();
          if (!disabled) setOver(true);
        }}
        onDragLeave={() => setOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          setOver(false);
          if (disabled) return;
          const dropped = e.dataTransfer?.files?.[0] ?? null;
          if (dropped) onSelect(dropped);
        }}
      >
        <input
          id={id}
          ref={inputRef}
          className="dropzone__input"
          type="file"
          accept={accept}
          aria-labelledby={labelId}
          aria-describedby={hintId}
          aria-invalid={invalid || undefined}
          disabled={disabled}
          onChange={(e) => onSelect(e.target.files?.[0] ?? null)}
        />

        <span className="dropzone__icon" aria-hidden="true">
          <Icon name="upload" size={22} />
        </span>
        <span className="dropzone__title">{file ? file.name : emptyTitle}</span>
        <span className="dropzone__hint">
          {file ? `${(file.size / (1024 * 1024)).toFixed(1)} MB selected` : emptyHint}
        </span>
      </label>

      {hint && (
        <span id={hintId} className="field__hint">
          {hint}
        </span>
      )}
    </div>
  );
}
