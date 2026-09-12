/**
 * StatCard — a single backend-derived metric.
 *
 * `value` may be a number or a string, but never a fabricated placeholder:
 * when the backend cannot supply a value the caller renders the unavailable
 * state instead of a zero.
 */
import type { ReactNode } from 'react';
import { Icon, type IconName } from './Icon';

export type StatTone = 'brand' | 'good' | 'warn' | 'info';

export function StatCard({
  label,
  value,
  note,
  icon,
  tone = 'brand',
}: {
  label: string;
  value: ReactNode;
  note?: ReactNode;
  icon?: IconName;
  tone?: StatTone;
}) {
  return (
    <div className="stat-card" aria-label={label}>
      <div className="stat-card__top">
        <span className="stat-card__label">{label}</span>
        {icon && (
          <span
            className={`stat-card__icon${tone !== 'brand' ? ` stat-card__icon--${tone}` : ''}`}
            aria-hidden="true"
          >
            <Icon name={icon} size={18} />
          </span>
        )}
      </div>
      <span className="stat-card__value">{value}</span>
      {note && <span className="stat-card__note">{note}</span>}
    </div>
  );
}
