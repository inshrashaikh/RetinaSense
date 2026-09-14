/**
 * SafetySection — the project's safety principles, stated in the repository's
 * own terms. No certification, approval or performance claim is made.
 */
import { Icon, type IconName } from '../ui/Icon';
import { DISCLAIMER } from '../DisclaimerFooter';

const ITEMS: { icon: IconName; title: string; body: string }[] = [
  {
    icon: 'info',
    title: 'Decision-support, not a diagnosis',
    body: DISCLAIMER,
  },
  {
    icon: 'shieldCheck',
    title: 'AI output and human decision stay separate',
    body: 'The AI prediction is immutable. The reviewer’s decision is stored as its own record, so the two can never be silently merged.',
  },
  {
    icon: 'alert',
    title: 'Nothing is fabricated',
    body: 'If a value cannot be produced — no grade, no Grad-CAM artifact, no report — the interface says so instead of showing a placeholder.',
  },
  {
    icon: 'activity',
    title: 'Backend state is reported honestly',
    body: 'Engine and database availability come from the health endpoint. An unavailable engine is shown as unavailable, never as a success.',
  },
  {
    icon: 'lock',
    title: 'No patient-identifying data in the UI',
    body: 'Patient references are opaque tokens. The frontend stores no clinical record and never invents demographic detail.',
  },
  {
    icon: 'bookOpen',
    title: 'Research prototype',
    body: 'RetinaSense is a project prototype. It carries no regulatory certification and must not be relied on as a clinical device.',
  },
];

export function SafetySection() {
  return (
    <section className="l-section l-section--mint l-anchor" id="safety" aria-labelledby="safety-title">
      <div className="l-container">
        <div className="l-section__head">
          <span className="eyebrow">Safety &amp; trust</span>
          <h2 className="l-section__title" id="safety-title">
            Guardrails that are visible in the product
          </h2>
          <p className="l-section__lead">
            These are not marketing promises — they are constraints enforced by the
            pipeline and reflected in every screen of the console.
          </p>
        </div>

        <div className="l-trust">
          {ITEMS.map((item) => (
            <div className="l-trust__item" key={item.title}>
              <span className="l-trust__icon" aria-hidden="true">
                <Icon name={item.icon} size={19} />
              </span>
              <div>
                <p className="l-trust__title">{item.title}</p>
                <p className="l-trust__body">{item.body}</p>
              </div>
            </div>
          ))}
        </div>

        <div className="l-callout" role="note">
          <Icon name="alert" size={18} />
          <span>
            Every report and result carries the disclaimer. RetinaSense never claims a
            screening is a diagnosis, and never presents simulated demo values as a real
            clinical outcome.
          </span>
        </div>
      </div>
    </section>
  );
}
