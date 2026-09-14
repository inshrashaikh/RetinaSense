/**
 * Demo-mode scenario selector. Only visible in DEMO MODE.
 * Selects which simulated result the next screening produces.
 */
import { useState } from 'react';
import { getCurrentScenario, setCurrentScenario, type DemoScenario } from '../api/demo';
import { Card, CardBody, CardHeader } from './ui/Card';
import { Badge } from './ui/Badge';
import { Field, Select } from './ui/Form';

const OPTIONS: { value: DemoScenario; label: string }[] = [
  { value: 'good', label: 'Good quality · Moderate NPDR, confident' },
  { value: 'good-review', label: 'Good quality · low-confidence / review required' },
  { value: 'borderline', label: 'Borderline quality · Mild NPDR' },
  { value: 'ungradable', label: 'Ungradable · recapture requested' },
];

export function DemoScenarioSelect() {
  const [scenario, setScenario] = useState<DemoScenario>(getCurrentScenario());

  return (
    <Card aria-label="Demo scenario" className="card--mint">
      <CardHeader
        title="Demo scenario"
        subtitle="Choose the simulated outcome for the next screening"
        icon="sliders"
        bordered
        actions={<Badge tone="warn" icon="alert">Simulated data</Badge>}
      />
      <CardBody>
        <p className="note-text">
          This only affects the demo client — values are fixtures, not real results.
        </p>
        <Field label="Next screening outcome (DEMO)">
          <Select
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
          </Select>
        </Field>
      </CardBody>
    </Card>
  );
}
