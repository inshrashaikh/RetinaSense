/**
 * Persistent DEMO MODE banner. Shown whenever the app is running against the
 * demo client so no simulated medical-looking value can be mistaken for a real
 * screening result.
 */
import { Icon } from './ui/Icon';

export function DemoModeBanner() {
  return (
    <div className="demo-banner" role="alert">
      <Icon name="alert" size={16} />
      <span>
        <strong>DEMO MODE — SIMULATED DATA</strong> · These screens show simulated values
        to exercise the UI only. This is not a real screening and not a clinical result.
      </span>
    </div>
  );
}
