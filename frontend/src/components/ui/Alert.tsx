/**
 * Alert — inline feedback for success / information / warning / error.
 *
 * Error and warning alerts are announced (`role="alert"`); informational and
 * success alerts use `role="status"`. Backend failures keep their honest
 * meaning — an unavailable engine is never restyled as a success.
 */
import type { ReactNode } from 'react';
import { Icon, type IconName } from './Icon';

export type AlertVariant = 'success' | 'info' | 'warning' | 'error' | 'neutral';

const DEFAULT_ICON: Record<AlertVariant, IconName> = {
  success: 'checkCircle',
  info: 'info',
  warning: 'alert',
  error: 'alert',
  neutral: 'info',
};

export interface AlertProps {
  variant?: AlertVariant;
  title?: ReactNode;
  children?: ReactNode;
  icon?: IconName;
  /** Override the default ARIA role. */
  role?: 'alert' | 'status' | 'note';
  action?: ReactNode;
  className?: string;
}

export function Alert({
  variant = 'info',
  title,
  children,
  icon,
  role,
  action,
  className,
}: AlertProps) {
  const resolvedRole =
    role ?? (variant === 'error' || variant === 'warning' ? 'alert' : 'status');

  return (
    <div
      className={['alert', `alert--${variant}`, className ?? ''].filter(Boolean).join(' ')}
      role={resolvedRole}
    >
      <span className="alert__icon" aria-hidden="true">
        <Icon name={icon ?? DEFAULT_ICON[variant]} size={16} />
      </span>
      <div className="alert__content">
        {title && <p className="alert__title">{title}</p>}
        {children && <div className="alert__body">{children}</div>}
        {action && <div className="alert__action btn-row">{action}</div>}
      </div>
    </div>
  );
}
