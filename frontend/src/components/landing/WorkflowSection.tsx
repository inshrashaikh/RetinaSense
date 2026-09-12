/**
 * WorkflowSection — the five steps of a RetinaSense screening, presented so it
 * is obvious that AI assists and a human decides.
 */
const STEPS = [
  {
    title: 'Upload fundus image',
    body: 'Capture or upload a JPEG/PNG fundus photograph (up to 20 MB) together with the patient token, eye and PHC metadata.',
  },
  {
    title: 'Image quality assessment',
    body: 'A deterministic quality gate checks illumination, field-of-view coverage and sharpness before anything is graded.',
  },
  {
    title: 'AI-assisted grading',
    body: 'The DR model returns a grade, referability, confidence and uncertainty — an assistive result, never a diagnosis.',
  },
  {
    title: 'Human review',
    body: 'An ophthalmologist approves, overrides or requests a recapture. The original AI result is preserved verbatim.',
  },
  {
    title: 'Final decision & report',
    body: 'The reviewed decision is stored separately and a structured report is assembled from the real recorded data.',
  },
];

export function WorkflowSection() {
  return (
    <section className="l-section l-anchor" id="how-it-works" aria-labelledby="how-title">
      <div className="l-container">
        <div className="l-section__head">
          <span className="eyebrow">How it works</span>
          <h2 className="l-section__title" id="how-title">
            A clinical workflow, not a black box
          </h2>
          <p className="l-section__lead">
            Every screening moves through the same five stages. The quality gate can
            stop an image before grading, and the AI result always passes through a
            human before it becomes a decision.
          </p>
        </div>

        <ol className="l-flow">
          {STEPS.map((step, i) => (
            <li className="l-flow__step" key={step.title}>
              <span className="l-flow__num" aria-hidden="true">
                {String(i + 1).padStart(2, '0')}
              </span>
              <h3 className="l-flow__title">{step.title}</h3>
              <p className="l-flow__body">{step.body}</p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
