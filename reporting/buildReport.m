function report = buildReport(caseData, params)
%BUILDREPORT  Stage 9b: compose the structured final screening report.
%
%   report = buildReport(caseData, params)
%
%   Contract (§4.8):
%     report.data     struct  machine-readable subset of case
%     report.summary  string  concise rapid-review summary
%     report.filepath string  rendered report path; '' until renderReport
%     report.review   struct  embedded final review/decision
%
%   This report is decision-support only. It is not a diagnosis and does
%   not replace ophthalmologist review.

    if nargin < 2
        params = struct(); %#ok<NASGU>
    end

    % Validate minimum Case fields required by the report contract.
    required = {'meta', 'quality', 'grading', 'calibrated', ...
                'explain', 'evidence', 'review'};

    for i = 1:numel(required)
        if ~isfield(caseData, required{i})
            raiseError('buildReport', 'MissingCaseField', ...
                'caseData.%s is required to build the report.', ...
                required{i});
        end
    end

    % Normalize review so report.review is always predictable.
    review = caseData.review;

    if isempty(review) || ~isstruct(review)
        review = struct();
    end

    defaults = struct( ...
        'action', 'auto', ...
        'graderId', '', ...
        'overrideGrade', NaN, ...
        'finalReferral', false, ...
        'status', 'auto', ...
        'notes', '');

    fields = fieldnames(defaults);

    for i = 1:numel(fields)
        fieldName = fields{i};

        if ~isfield(review, fieldName) || isempty(review.(fieldName))
            review.(fieldName) = defaults.(fieldName);
        end
    end

    % Preserve structured machine-readable case information.
    reportData = struct( ...
        'image',      caseData.image, ...
        'imagePath',  caseData.imagePath, ...
        'meta',       caseData.meta, ...
        'quality',    caseData.quality, ...
        'grading',    caseData.grading, ...
        'calibrated', caseData.calibrated, ...
        'explain',    caseData.explain, ...
        'evidence',   caseData.evidence, ...
        'pipeline',   caseData.pipeline, ...
        'review',     review);

    % Human-readable summary.
    patientId = safeText(caseData.meta.patientId);
    eye       = safeText(caseData.meta.eye);
    quality   = safeText(caseData.quality.class);

    grade = caseData.grading.grade;
    confidence = caseData.calibrated.confidence;
    uncertainty = caseData.calibrated.uncertainty;
    referableProb = caseData.grading.referableProb;

    if ~isnumeric(grade) || isempty(grade) || ~isscalar(grade)
        grade = NaN;
    end

    if ~isnumeric(confidence) || isempty(confidence) || ~isscalar(confidence)
        confidence = NaN;
    end

    if ~isnumeric(uncertainty) || isempty(uncertainty) || ~isscalar(uncertainty)
        uncertainty = NaN;
    end

    if ~isnumeric(referableProb) || isempty(referableProb) || ~isscalar(referableProb)
        referableProb = NaN;
    end

    summary = sprintf( ...
        ['Patient %s (%s): image quality %s; AI DR grade %s ', ...
         '(referable=%d, referable probability=%s); ', ...
         'calibrated confidence=%s, uncertainty=%s; ', ...
         'review=%s; final referral=%d.'], ...
        patientId, ...
        eye, ...
        quality, ...
        formatNumber(grade, '%.0f'), ...
        logical(caseData.grading.referable), ...
        formatNumber(referableProb, '%.3f'), ...
        formatNumber(confidence, '%.3f'), ...
        formatNumber(uncertainty, '%.3f'), ...
        safeText(review.action), ...
        logical(review.finalReferral));

    disclaimer = [ ...
        'Screening decision-support only. ', ...
        'Not a diagnosis and not a replacement for an ophthalmologist.'];

    % renderReport owns the actual output file.
    report = struct( ...
        'data',       reportData, ...
        'summary',    summary, ...
        'filepath',   '', ...
        'disclaimer', disclaimer, ...
        'review',     review);

end


function txt = safeText(value)
%SAFETEXT Convert a scalar value to printable text.

    if isstring(value)
        if isempty(value)
            txt = '';
        else
            txt = char(value(1));
        end
    elseif ischar(value)
        txt = value;
    elseif isempty(value)
        txt = '';
    elseif isnumeric(value) && isscalar(value)
        txt = num2str(value);
    else
        txt = '<value>';
    end

end


function txt = formatNumber(value, formatSpec)
%FORMATNUMBER Format a finite numeric scalar or return n/a.

    if isempty(value) || ...
            ~isnumeric(value) || ...
            ~isscalar(value) || ...
            ~isfinite(value)

        txt = 'n/a';
        return;
    end

    txt = sprintf(formatSpec, value);

end