/**
 * HumanLoopSection — makes the AI → human → decision separation explicit,
 * mirroring the way the system actually stores the three records.
 */
import { Icon, type IconName } from '../ui/Icon';

const NODES: {
  label: string;
  title: string;
  body: string;
  icon: IconName;
  final?: boolean;
}[] = [
  {
    label: 'Step 1',
    title: 'AI prediction',
    body: 'Stored with its grade, referability, confidence and uncertainty. Marked as the original, immutable result.',
    icon: 'spark',
  },
  {
    label: 'Step 2',
    title: 'Clinical / human review',
    body: 'The ophthalmologist approves, overrides the grade, or requests a recapture — adding a reviewer id and notes.',
    icon: 'userCheck',
  },
  {
    label: 'Step 3',
    title: 'Final decision',
    body: 'The reviewed grade and referral are recorded separately and become the case outcome used in the report.',
    icon: 'shieldCheck',
    final: true,
  },
];

export function HumanLoopSection() {
  return (
    <section className="l-section l-anchor" id="human-in-the-loop" aria-labelledby="loop-title">
      <div className="l-container">
        <div className="l-grid-2">
          <div className="l-section__head l-section__head--flush">
            <span className="eyebrow">Human in the loop</span>
            <h2 className="l-section__title" id="loop-title">
              Two results, deliberately kept apart
            </h2>
            <p className="l-section__lead">
              A single number that silently blends machine output with clinical
              judgement is impossible to audit. RetinaSense keeps them as separate
              records, and the interface always shows which is which.
            </p>
            <p className="l-section__lead">
              When a reviewer disagrees with the model, the override is recorded as the
              final decision while the original AI grade stays exactly as produced — so
              the disagreement itself remains visible.
            </p>
          </div>

          <div className="l-loop">
            {NODES.map((node, i) => (
              <div key={node.title}>
                <div className={`l-loop__node${node.final ? ' l-loop__node--final' : ''}`}>
                  <span className="l-loop__icon" aria-hidden="true">
                    <Icon name={node.icon} size={19} />
                  </span>
                  <div>
                    <p className="l-loop__label">{node.label}</p>
                    <p className="l-loop__title">{node.title}</p>
                    <p className="l-loop__body">{node.body}</p>
                  </div>
                </div>
                {i < NODES.length - 1 && (
                  <p className="l-loop__arrow" aria-hidden="true">
                    <Icon name="chevronDown" size={18} />
                  </p>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
