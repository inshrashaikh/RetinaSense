/**
 * Breadcrumbs — lightweight trail for nested pages (case / report).
 */
import { navigate } from '../../router';

export interface Crumb {
  label: string;
  path?: string;
}

export function Breadcrumbs({ items }: { items: Crumb[] }) {
  if (items.length === 0) return null;
  return (
    <nav className="breadcrumbs" aria-label="Breadcrumb">
      <ol className="breadcrumbs__list">
        {items.map((item, i) => {
          const last = i === items.length - 1;
          return (
            <li className="breadcrumbs__item" key={`${item.label}-${i}`}>
              {item.path && !last ? (
                <button type="button" className="breadcrumbs__link" onClick={() => navigate(item.path!)}>
                  {item.label}
                </button>
              ) : (
                <span aria-current={last ? 'page' : undefined}>{item.label}</span>
              )}
              {!last && (
                <span className="breadcrumbs__sep" aria-hidden="true">
                  /
                </span>
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
