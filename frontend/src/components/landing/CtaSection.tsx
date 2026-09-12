/**
 * CtaSection — closing call to action.
 */
import { Button } from '../ui/Button';
import { navigate } from '../../router';

export function CtaSection() {
  return (
    <section className="l-cta" aria-labelledby="cta-title">
      <div className="l-container">
        <div className="l-cta__panel">
          <div>
            <h2 className="l-cta__title" id="cta-title">
              Ready to start a retinal screening?
            </h2>
            <p className="l-cta__lead">
              Run the quality gate and AI-assisted grading on a fundus image, then
              complete the human review that produces the final referral decision.
            </p>
          </div>
          <div className="l-cta__actions">
            <Button variant="primary" size="lg" icon="plus" onClick={() => navigate('/screening')}>
              Start screening
            </Button>
            <Button size="lg" icon="grid" onClick={() => navigate('/dashboard')}>
              Open dashboard
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}
