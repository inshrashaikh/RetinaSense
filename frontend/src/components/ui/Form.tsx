/**
 * Form primitives — Field (label + hint + error), Input, Select, Textarea and
 * SearchInput. The label wraps the control so assistive tech and
 * Testing Library's getByLabelText both resolve correctly.
 */
import type {
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from 'react';
import { Icon } from './Icon';

interface FieldProps {
  label: ReactNode;
  hint?: ReactNode;
  error?: ReactNode;
  children: ReactNode;
}

export function Field({ label, hint, error, children }: FieldProps) {
  return (
    <label className="field">
      <span className="field__label">{label}</span>
      {children}
      {hint && <span className="field__hint">{hint}</span>}
      {error && (
        <span className="field__hint" role="alert">
          <span className="error-text">{error}</span>
        </span>
      )}
    </label>
  );
}

export function Input({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={['input', className].filter(Boolean).join(' ')} {...rest} />;
}

export function Textarea({ className, ...rest }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea className={['textarea', className].filter(Boolean).join(' ')} {...rest} />;
}

export function Select({ className, children, ...rest }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select className={['select', className].filter(Boolean).join(' ')} {...rest}>
      {children}
    </select>
  );
}

export function SearchInput({
  label,
  className,
  ...rest
}: InputHTMLAttributes<HTMLInputElement> & { label: string }) {
  return (
    <div className={['search-input', className].filter(Boolean).join(' ')}>
      <span className="search-input__icon" aria-hidden="true">
        <Icon name="search" size={16} />
      </span>
      <input
        type="search"
        className="input search-input__field"
        aria-label={label}
        placeholder={rest.placeholder ?? label}
        {...rest}
      />
    </div>
  );
}
