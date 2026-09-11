/**
 * Status pill — text + color, never color alone.
 */
import type { ReactNode } from 'react';

type Tone = 'good' | 'warn' | 'bad' | 'neutral' | 'info';

const TONES: Record<Tone, { className: string }> = {
  good: { className: 'pill pill-good' },
  warn: { className: 'pill pill-warn' },
  bad: { className: 'pill pill-bad' },
  neutral: { className: 'pill pill-neutral' },
  info: { className: 'pill pill-info' },
};

export function StatusPill({ tone, label }: { tone: Tone; label: ReactNode }) {
  return (
    <span className={TONES[tone].className} data-tone={tone}>
      {label}
    </span>
  );
}