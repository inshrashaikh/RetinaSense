/**
 * Badge — status/classification label.
 *
 * Status is NEVER communicated by colour alone: every badge carries text and,
 * where meaningful, an icon.
 */
import type { ReactNode } from 'react';
import { Icon, type IconName } from './Icon';
import type { StatusTone } from '../../utils/format';

/** Status tones shared with the case/quality helpers, plus the brand tint. */
export type BadgeTone = StatusTone | 'brand';

export function Badge({
  tone = 'neutral',
  icon,
  children,
  size = 'md',
  className,
}: {
  tone?: BadgeTone;
  icon?: IconName;
  children: ReactNode;
  size?: 'md' | 'lg';
  className?: string;
}) {
  return (
    <span
      className={['badge', `badge--${tone}`, size === 'lg' ? 'badge--lg' : '', className ?? '']
        .filter(Boolean)
        .join(' ')}
      data-tone={tone}
    >
      {icon && <Icon name={icon} size={size === 'lg' ? 14 : 12} />}
      {children}
    </span>
  );
}
