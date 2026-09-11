/**
 * Error banner with role="alert" so screen readers announce it.
 */
export function ErrorBanner({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="error-banner" role="alert">
      <h3 className="error-banner-title">{title}</h3>
      <p className="error-banner-detail">{detail}</p>
    </div>
  );
}