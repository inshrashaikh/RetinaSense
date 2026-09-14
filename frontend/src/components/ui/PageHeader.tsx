/**
 * PageHeader / SectionHeader — consistent page and section title blocks.
 */
import type { ReactNode } from 'react';

export function PageHeader({
  title,
  subtitle,
  eyebrow,
  badges,
  actions,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  eyebrow?: ReactNode;
  badges?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="page-header">
      <div className="page-header__text">
        {eyebrow && <span className="eyebrow">{eyebrow}</span>}
        <div className="page-header__title-row">
          <h1 className="page-header__title">{title}</h1>
          {badges}
        </div>
        {subtitle && <p className="page-header__subtitle">{subtitle}</p>}
      </div>
      {actions && <div className="page-header__actions">{actions}</div>}
    </header>
  );
}

export function SectionHeader({
  title,
  hint,
  actions,
  icon,
}: {
  title: ReactNode;
  hint?: ReactNode;
  actions?: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <div className="section-header">
      <h2 className="section-header__title">
        {icon}
        {title}
      </h2>
      {hint && <span className="section-header__hint">{hint}</span>}
      {actions && <div className="btn-row">{actions}</div>}
    </div>
  );
}
