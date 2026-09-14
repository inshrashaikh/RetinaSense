/**
 * StatusPill — status presentation for cases and clinical states.
 *
 * Text + icon + colour, never colour alone.
 */
import type { ReactNode } from 'react';
import { Badge } from './ui/Badge';
import type { IconName } from './ui/Icon';
import type { StatusTone } from '../utils/format';

const DEFAULT_ICON: Record<StatusTone, IconName | undefined> = {
  good: 'checkCircle',
  warn: 'alert',
  bad: 'xCircle',
  info: 'info',
  neutral: undefined,
};

export function StatusPill({
  tone,
  label,
  icon,
}: {
  tone: StatusTone;
  label: ReactNode;
  icon?: IconName;
}) {
  return (
    <Badge tone={tone} icon={icon ?? DEFAULT_ICON[tone]}>
      {label}
    </Badge>
  );
}
