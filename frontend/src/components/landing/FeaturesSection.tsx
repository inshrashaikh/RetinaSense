/**
 * FeaturesSection — the product capabilities, one icon per card.
 */
import { Icon, type IconName } from '../ui/Icon';

const FEATURES: { icon: IconName; title: string; body: string }[] = [
  {
    icon: 'camera',
    title: 'Fundus image screening',
    body: 'Create a case, attach the fundus photograph and metadata, and run the screening pipeline from one form.',
  },
  {
    icon: 'gauge',
    title: 'Image quality gate',
    body: 'Ungradable images stop early with a recapture instruction instead of a meaningless grade.',
  },
  {
    icon: 'spark',
    title: 'AI-assisted prediction',
    body: 'Grade, referability, confidence and uncertainty are surfaced together so low-confidence cases stand out.',
  },
  {
    icon: 'scan',
    title: 'Explainability',
    body: 'Attention and evidence artifacts are reported only when the backend actually produced them.',
  },
  {
    icon: 'userCheck',
    title: 'Review workflow',
    body: 'A dedicated queue collects everything awaiting an ophthalmologist decision, with reviewer id and notes.',
  },
  {
    icon: 'layers',
    title: 'Case management',
    body: 'Search and filter the full case list, then open any case to see its complete screening history.',
  },
  {
    icon: 'file',
    title: 'Structured reports',
    body: 'Readable, printable reports grouped by quality, AI result, human review and final referral.',
  },
  {
    icon: 'shieldCheck',
    title: 'Audit-friendly separation',
    body: 'The original AI prediction and the human final decision are displayed and stored separately, always.',
  },
];

export function FeaturesSection() {
  return (
    <section className="l-section l-section--honeydew l-anchor" id="features" aria-labelledby="features-title">
      <div className="l-container">
        <div className="l-section__head l-section__head--center">
          <span className="eyebrow">Features</span>
          <h2 className="l-section__title" id="features-title">
            Everything the screening workflow needs
          </h2>
          <p className="l-section__lead">
            The console covers the full screening journey — from upload to referral
            report — while keeping the clinical safeguards visible at every step.
          </p>
        </div>

        <div className="l-grid-3">
          {FEATURES.map((feature) => (
            <article className="l-feature" key={feature.title}>
              <span className="l-feature__icon" aria-hidden="true">
                <Icon name={feature.icon} size={20} />
              </span>
              <h3 className="l-feature__title">{feature.title}</h3>
              <p className="l-feature__body">{feature.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
