/**
 * Single-style line icons. Stroke-based, currentColor, 24×24 viewBox.
 *
 * One family only — no emoji, no mixed sets. Each name maps to one or more
 * `<path>` `d` strings so an icon can keep its visual weight consistent.
 */
import type { SVGProps } from 'react';

export type IconName =
  | 'activity'
  | 'alert'
  | 'arrowLeft'
  | 'arrowRight'
  | 'bookOpen'
  | 'calendar'
  | 'camera'
  | 'check'
  | 'checkCircle'
  | 'chevronDown'
  | 'chevronRight'
  | 'clipboard'
  | 'clock'
  | 'download'
  | 'externalLink'
  | 'eye'
  | 'file'
  | 'filter'
  | 'gauge'
  | 'grid'
  | 'home'
  | 'hourglass'
  | 'image'
  | 'inbox'
  | 'info'
  | 'layers'
  | 'lock'
  | 'menu'
  | 'plus'
  | 'print'
  | 'refresh'
  | 'scan'
  | 'search'
  | 'shield'
  | 'shieldCheck'
  | 'sliders'
  | 'spark'
  | 'target'
  | 'upload'
  | 'user'
  | 'userCheck'
  | 'users'
  | 'workflow'
  | 'x'
  | 'xCircle';

const PATHS: Record<IconName, string[]> = {
  activity: ['M4 12h4l2.5-6 3 12 2.5-6H20'],
  alert: ['M12 9v4M12 17h.01M10.3 4.7 2.8 18a2 2 0 0 0 1.7 3h15a2 2 0 0 0 1.7-3L13.7 4.7a2 2 0 0 0-3.4 0Z'],
  arrowLeft: ['M19 12H5M11 18l-6-6 6-6'],
  arrowRight: ['M5 12h14M13 6l6 6-6 6'],
  bookOpen: [
    'M12 6.5C10 5 7.5 4.5 4 4.5v13c3.5 0 6 .5 8 2 2-1.5 4.5-2 8-2v-13c-3.5 0-6 .5-8 2Z',
    'M12 6.5v13',
  ],
  calendar: [
    'M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1Z',
    'M8 3v4M16 3v4M4 11h16',
  ],
  camera: [
    'M4 8h3l2-2h6l2 2h3v12H4V8Z',
    'M12 11.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Z',
  ],
  check: ['M5 12.5 9.5 17 19 7.5'],
  checkCircle: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M8.4 12.2l2.4 2.4 4.8-4.8'],
  chevronDown: ['m6 9 6 6 6-6'],
  chevronRight: ['m9 6 6 6-6 6'],
  clipboard: [
    'M9 5h6M9 5a2 2 0 0 0 2 2h2a2 2 0 0 0 2-2',
    'M9 5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2',
    'M8 7H6a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-2',
  ],
  clock: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M12 7.5V12l3 2'],
  download: ['M12 4v10M8 10l4 4 4-4M5 19h14'],
  externalLink: ['M14 5h5v5M19 5l-7 7M18 14v4a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h4'],
  eye: [
    'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z',
    'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6Z',
  ],
  file: ['M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z', 'M14 3v5h5'],
  filter: ['M4 6h16M7 12h10M10 18h4'],
  gauge: ['M4.5 18a9 9 0 1 1 15 0', 'M12 13.5 15.5 10'],
  grid: [
    'M5 4h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1Z',
    'M15 4h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1Z',
    'M5 14h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z',
    'M15 14h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1h-4a1 1 0 0 1-1-1v-4a1 1 0 0 1 1-1Z',
  ],
  home: ['M4 11.5 12 4l8 7.5V20a1 1 0 0 1-1 1h-5v-6H10v6H5a1 1 0 0 1-1-1v-8.5Z'],
  hourglass: ['M8 4h8M8 20h8', 'M8 4c0 4 4 4 4 8s-4 4-4 8M16 4c0 4-4 4-4 8s4 4 4 8'],
  image: [
    'M5 5h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z',
    'M8 10a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z',
    'M4 17l5-6 3 4 2-2 6 4',
  ],
  inbox: [
    'M4 13V6a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v7',
    'M4 13h4l1.5 3h5L16 13h4',
    'M4 13v5a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-5',
  ],
  info: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M12 11v6M12 8h.01'],
  layers: ['M12 3 3 8l9 5 9-5-9-5Z', 'M3 12l9 5 9-5M3 16.5l9 5 9-5'],
  lock: ['M7 11V8a5 5 0 0 1 10 0v3', 'M6 11h12a1 1 0 0 1 1 1v7a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1Z'],
  menu: ['M4 7h16M4 12h16M4 17h16'],
  plus: ['M12 5v14M5 12h14'],
  print: [
    'M8 9V4h8v5',
    'M8 17H6a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-2',
    'M8 14h8v6H8v-6Z',
  ],
  refresh: [
    'M20.5 12a8.5 8.5 0 0 0-14.4-6.1L4 8',
    'M4 4v4h4',
    'M3.5 12a8.5 8.5 0 0 0 14.4 6.1L20 16',
    'M20 20v-4h-4',
  ],
  scan: [
    'M4 9V6a2 2 0 0 1 2-2h3M15 4h3a2 2 0 0 1 2 2v3',
    'M20 15v3a2 2 0 0 1-2 2h-3M9 20H6a2 2 0 0 1-2-2v-3',
    'M4 12h16',
  ],
  search: ['M11 5a6 6 0 1 0 0 12 6 6 0 0 0 0-12Z', 'M20 20l-4.3-4.3'],
  shield: ['M12 3 5 6v6c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6l-7-3Z'],
  shieldCheck: ['M12 3 5 6v6c0 4.5 3 7.5 7 9 4-1.5 7-4.5 7-9V6l-7-3Z', 'M9.3 12.1l1.9 1.9 3.5-3.5'],
  sliders: ['M4 8h9M17 8h3M4 16h3M11 16h9', 'M15 5.5v5M9 13.5v5'],
  spark: [
    'M12 3v4M12 17v4M4.9 6.5l2.8 2.8M16.3 14.7l2.8 2.8M3 12h4M17 12h4M4.9 17.5l2.8-2.8M16.3 9.3l2.8-2.8',
  ],
  target: [
    'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z',
    'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z',
  ],
  upload: ['M12 16V6M8 10l4-4 4 4M5 19h14'],
  user: ['M16 19v-1.5A3.5 3.5 0 0 0 12.5 14h-5A3.5 3.5 0 0 0 4 17.5V19', 'M10 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z'],
  userCheck: [
    'M14 19v-1.5A3.5 3.5 0 0 0 10.5 14h-4A3.5 3.5 0 0 0 3 17.5V19',
    'M8.5 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
    'M15.5 12.6l1.8 1.8 3.2-3.2',
  ],
  users: [
    'M16 19v-1.5A3.5 3.5 0 0 0 12.5 14h-5A3.5 3.5 0 0 0 4 17.5V19',
    'M9.5 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z',
    'M20 19v-1.2A2.8 2.8 0 0 0 17.2 15H16',
    'M16.5 11a2.5 2.5 0 1 0 0-4',
  ],
  workflow: ['M4 4h6v4H4V4Z', 'M14 16h6v4h-6v-4Z', 'M7 8v5a3 3 0 0 0 3 3h4'],
  x: ['M6 6l12 12M18 6 6 18'],
  xCircle: ['M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Z', 'M9 9l6 6M15 9l-6 6'],
};

export function Icon({
  name,
  size = 20,
  className,
  ...rest
}: { name: IconName; size?: number } & SVGProps<SVGSVGElement>) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden={rest['aria-label'] ? undefined : true}
      {...rest}
    >
      {PATHS[name].map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  );
}
