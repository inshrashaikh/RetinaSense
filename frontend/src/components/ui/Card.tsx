/**
 * Card — the surface primitive every panel is built from.
 *
 * `Card` renders a <section> by default so an `aria-label` keeps producing a
 * landmark region (used by the AI-prediction vs final-decision separation).
 */
import type { ElementType, ReactNode } from 'react';
import { Icon, type IconName } from './Icon';

interface CardProps {
  as?: ElementType;
  className?: string;
  children: ReactNode;
  'aria-label'?: string;
}

export function Card({ as: Tag = 'section', className, children, ...rest }: CardProps) {
  return (
    <Tag className={['card', className].filter(Boolean).join(' ')} {...rest}>
      {children}
    </Tag>
  );
}

interface CardHeaderProps {
  title: ReactNode;
  subtitle?: ReactNode;
  icon?: IconName;
  actions?: ReactNode;
  bordered?: boolean;
  id?: string;
  headingLevel?: 'h2' | 'h3' | 'h4';
}

export function CardHeader({
  title,
  subtitle,
  icon,
  actions,
  bordered = false,
  id,
  headingLevel: Heading = 'h2',
}: CardHeaderProps) {
  return (
    <div className={['card__header', bordered ? 'card__header--bordered' : ''].filter(Boolean).join(' ')}>
      <div className="card__title-group">
        {icon && (
          <span className="card__icon" aria-hidden="true">
            <Icon name={icon} size={18} />
          </span>
        )}
        <span>
          <Heading className="card__title" id={id}>
            {title}
          </Heading>
          {subtitle && <span className="card__subtitle">{subtitle}</span>}
        </span>
      </div>
      {actions && <div className="btn-row">{actions}</div>}
    </div>
  );
}

export function CardBody({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={['card__body', className].filter(Boolean).join(' ')}>{children}</div>;
}

export function CardFooter({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={['card__footer', className].filter(Boolean).join(' ')}>{children}</div>;
}

/** A labelled definition row: label on the left, value on the right. */
export function Row({
  label,
  children,
  strong = false,
}: {
  label: ReactNode;
  children: ReactNode;
  strong?: boolean;
}) {
  return (
    <div className="row">
      <span className="row__label">{label}</span>
      <span className={['row__value', strong ? 'row__value--strong' : ''].filter(Boolean).join(' ')}>
        {children}
      </span>
    </div>
  );
}
