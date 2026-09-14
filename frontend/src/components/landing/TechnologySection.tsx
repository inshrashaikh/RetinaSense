/**
 * TechnologySection — what is actually under the hood, described in the
 * project's own terminology with no performance claims.
 */
import { Icon, type IconName } from '../ui/Icon';

const PILLARS: { icon: IconName; title: string; body: string }[] = [
  {
    icon: 'gauge',
    title: 'Retinal image quality assessment',
    body: 'Threshold-driven checks configured in config/quality_thresholds.m decide whether an image is good, borderline or ungradable.',
  },
  {
    icon: 'spark',
    title: 'AI-assisted DR grading',
    body: 'A diabetic retinopathy classifier returns a 0–4 grade with referability, confidence and uncertainty for the clinician to weigh.',
  },
  {
    icon: 'scan',
    title: 'Explainability / evidence',
    body: 'When Grad-CAM or lesion-evidence artifacts exist on the backend they are reported as such. The UI never draws or invents an overlay.',
  },
  {
    icon: 'workflow',
    title: 'Human-in-the-loop verification',
    body: 'Approve, override or recapture is recorded as a decision separate from the AI output, which stays immutable for audit.',
  },
  {
    icon: 'file',
    title: 'Structured reporting',
    body: 'Reports are assembled by the pipeline from stored quality, AI, review and decision records — never generated client-side.',
  },
];

export function TechnologySection() {
  return (
    <section className="l-section l-anchor" id="technology" aria-labelledby="tech-title">
      <div className="l-container">
        <div className="l-grid-2">
          <div className="l-section__head l-section__head--flush">
            <span className="eyebrow">Technology</span>
            <h2 className="l-section__title" id="tech-title">
              Deterministic gates around an assistive model
            </h2>
            <p className="l-section__lead">
              RetinaSense is built as a chain of small, inspectable stages instead of a
              single opaque answer. Configuration lives in <code>config/</code>, results
              come only from the pipeline, and anything the pipeline cannot produce is
              reported as unavailable rather than filled in.
            </p>
            <ul className="plain-list">
              <li>Quality gate runs before grading, so ungradable images are never graded.</li>
              <li>AI output is stored verbatim; reviews are stored alongside it.</li>
              <li>Frontend values mirror the backend contract — no client-side medical logic.</li>
            </ul>
          </div>

          <div className="l-stack">
            {PILLARS.map((pillar) => (
              <article className="l-feature" key={pillar.title}>
                <span className="l-feature__icon" aria-hidden="true">
                  <Icon name={pillar.icon} size={20} />
                </span>
                <h3 className="l-feature__title">{pillar.title}</h3>
                <p className="l-feature__body">{pillar.body}</p>
              </article>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
