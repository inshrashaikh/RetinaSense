function review = submitReview(caseData, reviewerInput, params)
%SUBMITREVIEW  Stage 9a: human review decision state machine.
%
%   review = submitReview(caseData, reviewerInput, params)
%
%   reviewerInput (struct): action ('approve'|'override'|'recapture'),
%     graderId (string), overrideGrade (0..4 or NaN), notes (string).
%     Pass reviewerInput = [] to mark the case as auto-review only.
%
%   CONTRACT (docs/ARCHITECTURE.md §4.7):
%     review.action        'approve' | 'override' | 'recapture' | 'auto'
%     review.graderId      string
%     review.overrideGrade 0..4 | NaN
%     review.finalReferral logical (final binary referral decision)
%     review.status        'auto' | 'approved' | 'overridden' | 'recapture'
%     review.notes         string
%
%   Final referral respects the referable-DR threshold (Level 2+): an override
%   sets the final grade; otherwise the AI grade stands.

    if nargin < 3 || isempty(params); params = experiment_config(); end

    if isempty(reviewerInput)
        % No human action captured yet.
        finalGrade = caseData.grading.grade;
        review = struct( ...
            'action',        'auto', ...
            'graderId',      '', ...
            'overrideGrade', NaN, ...
            'finalReferral', finalGrade >= params.referThreshold, ...
            'status',        'auto', ...
            'notes',         '');
        return;
    end

    r = reviewerInput;
    switch r.action
        case 'approve'
            finalGrade    = caseData.grading.grade;
            finalReferral = finalGrade >= params.referThreshold;
            review = struct( ...
                'action', 'approve', 'graderId', r.graderId, ...
                'overrideGrade', NaN, 'finalReferral', finalReferral, ...
                'status', 'approved', 'notes', r.notes);
        case 'override'
            g = r.overrideGrade;
            if isnan(g) || g < 0 || g > 4
                raiseError('submitReview', 'BadOverrideGrade', ...
                    'overrideGrade must be 0..4 (got %s).', num2str(g));
            end
            review = struct( ...
                'action', 'override', 'graderId', r.graderId, ...
                'overrideGrade', g, 'finalReferral', g >= params.referThreshold, ...
                'status', 'overridden', 'notes', r.notes);
        case 'recapture'
            review = struct( ...
                'action', 'recapture', 'graderId', r.graderId, ...
                'overrideGrade', NaN, 'finalReferral', false, ...
                'status', 'recapture', 'notes', r.notes);
        otherwise
            raiseError('submitReview', 'BadAction', ...
                'Unsupported action ''%s''.', r.action);
    end
end