function review = submitReview(caseData, reviewerInput, params)
%SUBMITREVIEW  Stage 9a: human review decision state machine.
%
%   review = submitReview(caseData, reviewerInput, params)
%
%   reviewerInput:
%     action        'approve' | 'override' | 'recapture'
%     graderId      reviewer identifier
%     overrideGrade 0..4 integer for override, otherwise NaN
%     notes         reviewer notes
%
%   Pass reviewerInput = [] to produce an automatic decision.
%
%   Contract (§4.7):
%     review.action         approve | override | recapture | auto
%     review.graderId       string
%     review.overrideGrade  0..4 | NaN
%     review.finalReferral   logical
%     review.status         auto | approved | overridden
%     review.notes          string

    if nargin < 3 || isempty(params)
        params = experiment_config();
    end

    validateCase(caseData);
    validateParams(params);

    aiGrade = caseData.grading.grade;
    referThreshold = params.referThreshold;

    % ---------------------------------------------------------------------
    % No reviewer input -> automatic decision.
    % ---------------------------------------------------------------------
    if isempty(reviewerInput)
        review = makeReview( ...
            'auto', ...
            '', ...
            NaN, ...
            logical(aiGrade >= referThreshold), ...
            'auto', ...
            '');
        return;
    end

    if ~isstruct(reviewerInput) || ~isscalar(reviewerInput)
        raiseError('submitReview', 'BadReviewerInput', ...
            'reviewerInput must be a scalar struct or [].');
    end

    r = reviewerInput;

    % Required reviewer input fields.
    requiredFields = {'action', 'graderId', 'overrideGrade', 'notes'};

    for i = 1:numel(requiredFields)
        if ~isfield(r, requiredFields{i})
            raiseError('submitReview', 'MissingReviewerField', ...
                'reviewerInput.%s is required.', ...
                requiredFields{i});
        end
    end

    action = normalizeText(r.action, 'action');
    graderId = normalizeText(r.graderId, 'graderId');
    notes = normalizeText(r.notes, 'notes');
    overrideGrade = r.overrideGrade;

    if isempty(graderId) && ~strcmp(action, 'auto')
        raiseError('submitReview', 'MissingGraderId', ...
            'graderId is required for human review actions.');
    end

    switch action

        case 'approve'
            % Human accepts the AI grade.
            review = makeReview( ...
                'approve', ...
                graderId, ...
                NaN, ...
                logical(aiGrade >= referThreshold), ...
                'approved', ...
                notes);

        case 'override'
            % Human replaces the AI grade.
            validateOverrideGrade(overrideGrade);

            finalReferral = logical(overrideGrade >= referThreshold);

            review = makeReview( ...
                'override', ...
                graderId, ...
                overrideGrade, ...
                finalReferral, ...
                'overridden', ...
                notes);

        case 'recapture'
            % The current report should not be treated as referred while
            % a new image is being requested.
            review = makeReview( ...
                'recapture', ...
                graderId, ...
                NaN, ...
                false, ...
                'approved', ...
                notes);

        otherwise
            raiseError('submitReview', 'BadAction', ...
                ['Unsupported action ''%s''. ', ...
                 'Expected approve, override, or recapture.'], ...
                action);
    end

end


function validateCase(caseData)

    if ~isstruct(caseData) || ~isscalar(caseData)
        raiseError('submitReview', 'BadCase', ...
            'caseData must be a scalar struct.');
    end

    if ~isfield(caseData, 'grading') || ...
            ~isstruct(caseData.grading)
        raiseError('submitReview', 'MissingGrading', ...
            'caseData.grading is required.');
    end

    if ~isfield(caseData.grading, 'grade')
        raiseError('submitReview', 'MissingGrade', ...
            'caseData.grading.grade is required.');
    end

    grade = caseData.grading.grade;

    if isempty(grade) || ...
            ~isnumeric(grade) || ...
            ~isscalar(grade) || ...
            ~isfinite(grade) || ...
            grade < 0 || ...
            grade > 4 || ...
            grade ~= floor(grade)

        raiseError('submitReview', 'BadGrade', ...
            'caseData.grading.grade must be an integer in 0..4.');
    end

end


function validateParams(params)

    if ~isstruct(params) || ~isscalar(params)
        raiseError('submitReview', 'BadParams', ...
            'params must be a scalar struct.');
    end

    if ~isfield(params, 'referThreshold')
        raiseError('submitReview', 'MissingReferThreshold', ...
            'params.referThreshold is required.');
    end

    threshold = params.referThreshold;

    if isempty(threshold) || ...
            ~isnumeric(threshold) || ...
            ~isscalar(threshold) || ...
            ~isfinite(threshold) || ...
            threshold < 0 || ...
            threshold > 4

        raiseError('submitReview', 'BadReferThreshold', ...
            'params.referThreshold must be a scalar in 0..4.');
    end

end


function validateOverrideGrade(value)

    if isempty(value) || ...
            ~isnumeric(value) || ...
            ~isscalar(value) || ...
            ~isfinite(value) || ...
            value < 0 || ...
            value > 4 || ...
            value ~= floor(value)

        raiseError('submitReview', 'BadOverrideGrade', ...
            'overrideGrade must be an integer in 0..4.');
    end

end


function txt = normalizeText(value, fieldName)

    if isstring(value)
        if ~isscalar(value)
            raiseError('submitReview', 'BadTextField', ...
                'reviewerInput.%s must be scalar text.', fieldName);
        end
        txt = char(value);

    elseif ischar(value)
        if size(value, 1) > 1
            raiseError('submitReview', 'BadTextField', ...
                'reviewerInput.%s must be scalar text.', fieldName);
        end
        txt = value;

    elseif isempty(value)
        txt = '';

    else
        raiseError('submitReview', 'BadTextField', ...
            'reviewerInput.%s must be text.', fieldName);
    end

end


function review = makeReview( ...
        action, graderId, overrideGrade, finalReferral, status, notes)

    review = struct( ...
        'action', action, ...
        'graderId', graderId, ...
        'overrideGrade', overrideGrade, ...
        'finalReferral', logical(finalReferral), ...
        'status', status, ...
        'notes', notes);

end