function filepath = renderReport(report, params)
%RENDERREPORT  Stage 9c: render the final screening report.
%
%   filepath = renderReport(report, params)
%
%   Produces a PDF report and a companion PNG preview. The returned filepath
%   is the PDF path. Missing explainability/evidence assets are rendered as
%   explicit placeholders; no AI output is invented.

    if nargin < 2 || isempty(params)
        p = paths();
        params = struct('out', p.output);
    end

    if ~isfield(params, 'out') || isempty(params.out)
        params.out = paths().output;
    end

    if ~exist(params.out, 'dir')
        mkdir(params.out);
    end

    timestamp = datestr(now, 'yyyymmdd_HHMMSSFFF');
    basename = sprintf('retinasense_report_%s', timestamp);

    if isfield(params, 'basename') && ~isempty(params.basename)
        basename = char(string(params.basename));
    end

    pdfPath = fullfile(params.out, [basename '.pdf']);
    pngPath = fullfile(params.out, [basename '.png']);

    % Create invisible figure for deterministic file rendering.
    fig = figure( ...
        'Visible', 'off', ...
        'Color', 'white', ...
        'Units', 'pixels', ...
        'Position', [50 50 1400 1900]);

    cleanupObj = onCleanup(@() closeFigure(fig)); %#ok<NASGU>

    tiledlayout(fig, 6, 2, ...
        'TileSpacing', 'compact', ...
        'Padding', 'compact');

    % ---------------------------------------------------------------------
    % 1. Title / summary
    % ---------------------------------------------------------------------
    nexttile([1 2]);

    axis off;

    title('RetinaSense Screening Report', ...
        'FontSize', 18, ...
        'FontWeight', 'bold');

    summaryText = '';
    if isfield(report, 'summary')
        summaryText = char(string(report.summary));
    end

    text(0, 0.75, summaryText, ...
        'Units', 'normalized', ...
        'FontSize', 11, ...
        'Interpreter', 'none', ...
        'VerticalAlignment', 'top');

    % ---------------------------------------------------------------------
    % 2. Case information
    % ---------------------------------------------------------------------
    nexttile;
    axis off;

    title('Case Information', ...
        'FontSize', 13, ...
        'FontWeight', 'bold');

    caseLines = makeCaseLines(report);

    text(0, 1, caseLines, ...
        'Units', 'normalized', ...
        'FontSize', 10, ...
        'VerticalAlignment', 'top', ...
        'Interpreter', 'none');

    % ---------------------------------------------------------------------
    % 3. Assessment information
    % ---------------------------------------------------------------------
    nexttile;
    axis off;

    title('Assessment', ...
        'FontSize', 13, ...
        'FontWeight', 'bold');

    assessmentLines = makeAssessmentLines(report);

    text(0, 1, assessmentLines, ...
        'Units', 'normalized', ...
        'FontSize', 10, ...
        'VerticalAlignment', 'top', ...
        'Interpreter', 'none');

    % ---------------------------------------------------------------------
    % 4. Fundus image
    % ---------------------------------------------------------------------
    nexttile;

    renderImageOrPlaceholder( ...
        getNestedField(report, {'data', 'image'}), ...
        'Fundus Image Unavailable');

    title('Fundus Image', ...
        'FontSize', 12, ...
        'FontWeight', 'bold');

    % ---------------------------------------------------------------------
    % 5. Grad-CAM / attention
    % ---------------------------------------------------------------------
    nexttile;

    gradCam = getNestedField(report, {'data', 'explain', 'gradCam'});

    if isUsableImage(gradCam)
        imagesc(gradCam);
        axis image off;
        colormap(gca, 'turbo');
    else
        axis off;
        text(0.5, 0.5, ...
            'Grad-CAM / attention image unavailable', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
    end

    title('Model Attention (Grad-CAM)', ...
        'FontSize', 12, ...
        'FontWeight', 'bold');

    % ---------------------------------------------------------------------
    % 6. Evidence overlay
    % ---------------------------------------------------------------------
    nexttile;

    evidenceOverlay = ...
        getNestedField(report, {'data', 'explain', 'evidenceOverlay'});

    if isUsableImage(evidenceOverlay)
        imagesc(evidenceOverlay);
        axis image off;
    elseif hasLesionEvidence(report)
        renderImageOrPlaceholder( ...
            getNestedField(report, {'data', 'image'}), ...
            'Evidence overlay unavailable');
    else
        axis off;
        text(0.5, 0.5, ...
            'No lesion evidence available', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
    end

    title('Evidence / Lesion Overlay', ...
        'FontSize', 12, ...
        'FontWeight', 'bold');

    % ---------------------------------------------------------------------
    % 7. Review
    % ---------------------------------------------------------------------
    nexttile;
    axis off;

    title('Human Review', ...
        'FontSize', 13, ...
        'FontWeight', 'bold');

    reviewLines = makeReviewLines(report);

    text(0, 1, reviewLines, ...
        'Units', 'normalized', ...
        'FontSize', 10, ...
        'VerticalAlignment', 'top', ...
        'Interpreter', 'none');

    % ---------------------------------------------------------------------
    % 8. Disclaimer
    % ---------------------------------------------------------------------
    nexttile([1 2]);
    axis off;

    disclaimer = ...
        'Screening decision-support only. Not a diagnosis and not a replacement for an ophthalmologist.';

    if isfield(report, 'disclaimer') && ~isempty(report.disclaimer)
        disclaimer = char(string(report.disclaimer));
    end

    text(0.5, 0.5, disclaimer, ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 10, ...
        'FontWeight', 'bold', ...
        'Interpreter', 'none');

    % ---------------------------------------------------------------------
    % Export PDF and PNG.
    % ---------------------------------------------------------------------
    exportSuccessful = false;

    if exist('exportgraphics', 'file') == 2
        try
            exportgraphics(fig, pdfPath, ...
                'ContentType', 'vector');
            exportgraphics(fig, pngPath, ...
                'Resolution', 150);
            exportSuccessful = true;
        catch
            exportSuccessful = false;
        end
    end

    if ~exportSuccessful
        try
            print(fig, pdfPath, '-dpdf', '-bestfit');
            print(fig, pngPath, '-dpng', '-r150');
            exportSuccessful = true;
        catch ME
            raiseError('renderReport', 'ExportFailed', ...
                'Could not render report: %s', ME.message);
        end
    end

    if ~exist(pdfPath, 'file')
        raiseError('renderReport', 'WriteFailed', ...
            'Rendered PDF was not created: %s', pdfPath);
    end

    filepath = pdfPath;

end


function lines = makeCaseLines(report)

    meta = getNestedField(report, {'data', 'meta'});
    quality = getNestedField(report, {'data', 'quality'});

    patientId = getStructField(meta, 'patientId', 'n/a');
    eye = getStructField(meta, 'eye', 'n/a');
    timestamp = getStructField(meta, 'timestamp', 'n/a');
    phcId = getStructField(meta, 'phcId', 'n/a');

    qualityClass = getStructField(quality, 'class', 'n/a');
    qualityScore = getStructField(quality, 'score', NaN);

    lines = sprintf([ ...
        'Patient ID: %s\n', ...
        'Eye: %s\n', ...
        'Timestamp: %s\n', ...
        'PHC ID: %s\n\n', ...
        'Image quality: %s\n', ...
        'Quality score: %s'], ...
        safeText(patientId), ...
        safeText(eye), ...
        safeText(timestamp), ...
        safeText(phcId), ...
        safeText(qualityClass), ...
        safeNumber(qualityScore));

end


function lines = makeAssessmentLines(report)

    grading = getNestedField(report, {'data', 'grading'});
    calibrated = getNestedField(report, {'data', 'calibrated'});

    grade = getStructField(grading, 'grade', NaN);
    referable = getStructField(grading, 'referable', false);
    referableProb = getStructField(grading, 'referableProb', NaN);

    confidence = getStructField(calibrated, 'confidence', NaN);
    uncertainty = getStructField(calibrated, 'uncertainty', NaN);
    reviewRequired = getStructField(calibrated, 'reviewRequired', false);

    lines = sprintf([ ...
        'AI DR grade: %s\n', ...
        'AI referable: %s\n', ...
        'Referable probability: %s\n\n', ...
        'Calibrated confidence: %s\n', ...
        'Uncertainty: %s\n', ...
        'Review required: %s'], ...
        safeNumber(grade), ...
        safeLogical(referable), ...
        safeNumber(referableProb), ...
        safeNumber(confidence), ...
        safeNumber(uncertainty), ...
        safeLogical(reviewRequired));

end


function lines = makeReviewLines(report)

    review = getNestedField(report, {'review'});

    action = getStructField(review, 'action', 'n/a');
    graderId = getStructField(review, 'graderId', 'n/a');
    overrideGrade = getStructField(review, 'overrideGrade', NaN);
    finalReferral = getStructField(review, 'finalReferral', false);
    status = getStructField(review, 'status', 'n/a');
    notes = getStructField(review, 'notes', '');

    lines = sprintf([ ...
        'Action: %s\n', ...
        'Grader ID: %s\n', ...
        'Override grade: %s\n', ...
        'Final referral: %s\n', ...
        'Status: %s\n\n', ...
        'Notes:\n%s'], ...
        safeText(action), ...
        safeText(graderId), ...
        safeNumber(overrideGrade), ...
        safeLogical(finalReferral), ...
        safeText(status), ...
        safeText(notes));

end


function renderImageOrPlaceholder(imageData, placeholderText)

    if isUsableImage(imageData)
        imagesc(imageData);
        axis image off;
    else
        axis off;
        text(0.5, 0.5, placeholderText, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
    end

end


function tf = isUsableImage(imageData)

    tf = isnumeric(imageData) || islogical(imageData);

    if ~tf || isempty(imageData)
        tf = false;
        return;
    end

    if ndims(imageData) < 2 || ndims(imageData) > 3
        tf = false;
        return;
    end

    tf = any(isfinite(double(imageData(:))));

end


function tf = hasLesionEvidence(report)

    evidence = getNestedField(report, {'data', 'evidence'});

    tf = false;

    if ~isstruct(evidence) || ~isfield(evidence, 'lesions')
        return;
    end

    lesionNames = ...
        {'exudates', 'hemorrhages', 'microaneurysms', 'neoVasc'};

    for i = 1:numel(lesionNames)
        lesion = evidence.lesions.(lesionNames{i});

        if ~isstruct(lesion)
            continue;
        end

        if isfield(lesion, 'map') && isUsableImage(lesion.map)
            tf = true;
            return;
        end

        if isfield(lesion, 'count') && ...
                isnumeric(lesion.count) && ...
                isscalar(lesion.count) && ...
                lesion.count > 0
            tf = true;
            return;
        end
    end

end


function value = getNestedField(s, fields)

    value = [];

    current = s;

    for i = 1:numel(fields)
        if ~isstruct(current) || ~isfield(current, fields{i})
            return;
        end

        current = current.(fields{i});
    end

    value = current;

end


function value = getStructField(s, fieldName, defaultValue)

    value = defaultValue;

    if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
        value = s.(fieldName);
    end

end


function txt = safeText(value)

    if isstring(value)
        txt = char(value(1));
    elseif ischar(value)
        txt = value;
    elseif isempty(value)
        txt = 'n/a';
    elseif isnumeric(value) && isscalar(value)
        txt = num2str(value);
    else
        txt = '<value>';
    end

end


function txt = safeNumber(value)

    if isempty(value) || ...
            ~isnumeric(value) || ...
            ~isscalar(value) || ...
            ~isfinite(value)
        txt = 'n/a';
        return;
    end

    txt = sprintf('%.3f', value);

end


function txt = safeLogical(value)

    if isempty(value)
        txt = 'false';
    elseif islogical(value)
        txt = lower(char(string(value)));
    elseif isnumeric(value) && isscalar(value)
        txt = lower(char(string(logical(value))));
    else
        txt = '<value>';
    end

end


function closeFigure(fig)

    if ishghandle(fig)
        close(fig);
    end

end