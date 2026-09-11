/** Small formatting helpers. */

export function formatScore(score: number | null | undefined): string {
  if (score === null || score === undefined || Number.isNaN(score)) return '—';
  return `${(score * 100).toFixed(0)}%`;
}

export function formatPercent(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) return '—';
  return `${(value * 100).toFixed(0)}%`;
}

export function formatGradeLabel(grade: number | null | undefined, gradeLabel: string | null | undefined): string {
  if (grade === null || grade === undefined) {
    return gradeLabel ?? 'No grade';
  }
  return gradeLabel ?? String(grade);
}

/** Human-friendly quality class display. */
export function qualityClassLabel(cls: string | null | undefined): string {
  switch ((cls ?? '').toLowerCase()) {
    case 'good':
      return 'Good';
    case 'borderline':
      return 'Borderline';
    case 'ungradable':
      return 'Ungradable';
    default:
      return 'Not assessed';
  }
}

export type StatusTone = 'good' | 'warn' | 'bad' | 'neutral' | 'info';

/** Map an effective case status to a StatusPill tone. */
export function statusTone(status: string | null | undefined): StatusTone {
  switch ((status ?? '').toLowerCase()) {
    case 'completed':
      return 'info';
    case 'reviewed':
      return 'good';
    case 'recapture_required':
      return 'warn';
    case 'created':
      return 'neutral';
    default:
      return 'neutral';
  }
}

/** Human-friendly effective case status label. */
export function statusLabel(status: string | null | undefined): string {
  switch ((status ?? '').toLowerCase()) {
    case 'completed':
      return 'Screened — pending review';
    case 'reviewed':
      return 'Reviewed';
    case 'recapture_required':
      return 'Recapture required';
    case 'created':
      return 'Created';
    default:
      return status ?? 'Unknown';
  }
}