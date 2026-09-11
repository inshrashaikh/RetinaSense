/**
 * Persistent DEMO MODE banner. Shown whenever the app is running against the
 * demo client so no simulated medical-looking value can be mistaken for a real
 * screening result.
 */
export function DemoModeBanner() {
  return (
    <div className="demo-banner" role="alert">
      <strong>DEMO MODE — SIMULATED DATA</strong> · This screen shows simulated
      values to exercise the UI only. It is not a real screening and not a
      clinical result.
    </div>
  );
}