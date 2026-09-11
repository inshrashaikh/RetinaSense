/**
 * The screening decision-support disclaimer required on all output.
 */
export const DISCLAIMER =
  'Screening decision-support only. Not a diagnosis and not a replacement for an ophthalmologist.';

export function DisclaimerFooter() {
  return (
    <footer className="disclaimer" role="note">
      <p>{DISCLAIMER}</p>
    </footer>
  );
}