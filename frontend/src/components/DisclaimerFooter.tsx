/**
 * The screening decision-support disclaimer required on all output.
 * Presented as a calm, readable block — never a dominating red banner.
 */
import { Icon } from './ui/Icon';

export const DISCLAIMER =
  'Screening decision-support only. Not a diagnosis and not a replacement for an ophthalmologist.';

export function DisclaimerFooter({ text = DISCLAIMER }: { text?: string }) {
  return (
    <div className="l-footer__disclaimer" role="note">
      <Icon name="shieldCheck" size={18} />
      <span>{text}</span>
    </div>
  );
}
