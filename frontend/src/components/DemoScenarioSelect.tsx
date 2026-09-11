/**
 * Demo-mode scenario selector. Only visible in DEMO MODE.
 * Selects which simulated result the next screening produces.
 */
import { useState } from 'react';
import { getCurrentScenario, setCurrentScenario, type DemoScenario } from '../api/demo';

const OPTIONS: { value: DemoScenario; label: string }[] = [
  { value: 'good', label: 'Good quality · Moderate NPDR, confident' },
  { value: 'good-review', label: 'Good quality · low-confidence / review required' },
  { value: 'borderline', label: 'Borderline quality · Mild NPDR' },
  { value: 'ungradable', label: 'Ungradable · recapture requested' },
];

export function DemoScenarioSelect() {
  const [scenario, setScenario] = useState<DemoScenario>(getCurrentScenario());

  return (
    <div className="panel demo-panel" role="note">
      <h2 className="panel-title">Demo scenario</h2>
      <p className="note-text">
        Choose the simulated outcome for the <em>next</em> screening. This only
        affects the demo client — values are fixtures, not real results.
      </p>
      <label className="field">
        <span className="field-label">Next screening outcome (DEMO)</span>
        <select
          value={scenario}
          onChange={(e) => {
            const v = e.target.value as DemoScenario;
            setScenario(v);
            setCurrentScenario(v);
          }}
        >
          {OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      </label>
    </div>
  );
}