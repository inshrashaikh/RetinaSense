/**
 * Button — one consistent control for every action.
 *
 * Variants: primary | secondary | ghost | danger | link
 * Sizes:    sm | md | lg
 * Supports icons, loading, disabled and (when `href` is given) renders a real
 * anchor so navigation serves as a genuine link.
 */
import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { Icon, type IconName } from './Icon';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'link';
export type ButtonSize = 'sm' | 'md' | 'lg';

interface CommonProps {
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: IconName;
  iconRight?: IconName;
  loading?: boolean;
  block?: boolean;
  className?: string;
  children?: ReactNode;
}

type Props = CommonProps &
  Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'className' | 'children'> & {
    /** When set, the component renders an <a> element instead of a <button>. */
    href?: string;
  };

export function Button({
  variant = 'secondary',
  size = 'md',
  icon,
  iconRight,
  loading = false,
  block = false,
  className,
  children,
  href,
  disabled,
  type = 'button',
  ...rest
}: Props) {
  const classes = [
    'btn',
    `btn--${variant}`,
    size !== 'md' ? `btn--${size}` : '',
    block ? 'btn--block' : '',
    !children ? 'btn--icon' : '',
    className ?? '',
  ]
    .filter(Boolean)
    .join(' ');

  const content = (
    <>
      {loading && <span className="btn__spinner" aria-hidden="true" />}
      {!loading && icon && <Icon name={icon} size={size === 'lg' ? 19 : 17} />}
      {children}
      {iconRight && <Icon name={iconRight} size={size === 'lg' ? 19 : 17} />}
    </>
  );

  if (href) {
    return (
      <a className={classes} href={href} {...(rest as Record<string, unknown>)}>
        {content}
      </a>
    );
  }

  return (
    <button
      {...rest}
      type={type}
      className={classes}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
    >
      {content}
    </button>
  );
}
