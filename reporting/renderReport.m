function filepath = renderReport(report, params)
%RENDERREPORT  Stage 9c: render the report to a file.
%
%   filepath = renderReport(report, params)
%
%   Generates a professional screening report with:
%     - Case information and DR grading
%     - Retinal images with overlays
%     - Evidence summary
%     - Disclaimer
%
%   Output format: PDF (preferred) or PNG/TEXT fallback
%   Layout driven by config/report_config.m.
%
%   References: docs/ARCHITECTURE.md §4.8, §9

    if nargin < 2 || isempty(params)
        p = paths();
        params = struct('out', p.output);
    end
    if ~isfield(params, 'out')
        params.out = paths().output;
    end
    if ~exist(params.out, 'dir')
        mkdir(params.out);
    end

    % Load report config for layout/format settings
    rc = report_config();

    % --- Determine output format ---
    formats = {'pdf', 'png', 'txt'};
    if isfield(rc, 'format') && ~strcmp(rc.format, 'auto')
        % Prioritize configured format
        fmtOrder = {rc.format};
        for i = 1:numel(formats)
            if ~strcmp(formats{i}, rc.format)
                fmtOrder{end+1} = formats{i}; %#ok<AGROW>
            end
        end
        formats = fmtOrder;
    end

    filepath = '';
    renderSuccess = false;

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    baseName = sprintf(rc.filenameTemplate, timestamp);

    for fmtIdx = 1:numel(formats)
        fmt = formats{fmtIdx};
        try
            switch fmt
                case 'pdf'
                    filepath = fullfile(params.out, [baseName, '.pdf']);
                    renderSuccess = renderReportPDF(report, filepath, params);
                case 'png'
                    filepath = fullfile(params.out, [baseName, '.png']);
                    renderSuccess = renderReportPNG(report, filepath, params);
                case 'txt'
                    filepath = fullfile(params.out, [baseName, '.txt']);
                    renderSuccess = renderReportText(report, filepath, params);
            end
            if renderSuccess && exist(filepath, 'file')
                break;
            end
        catch ME
            % Try next format
            logMessage('warn', 'renderReport', ...
                sprintf('Format %s failed: %s', fmt, ME.message));
            filepath = '';
            renderSuccess = false;
        end
    end

    if ~renderSuccess || isempty(filepath)
        raiseError('renderReport', 'AllFormatsFailed', ...
            'Could not render report in any supported format.');
    end
end

function success = renderReportPDF(report, filepath, params)
%RENDERREPORT_PDF  Render report as PDF using exportgraphics/print.
%
%   Creates a multi-page PDF with:
%   Page 1: Case info, DR result, quality, disclaimer
%   Page 2: Original image + Grad-CAM + Evidence overlay
%   Page 3: Evidence detail tables

    rc = report_config();
    pw = rc.pageSize(1);  % width in inches
    ph = rc.pageSize(2);  % height in inches

    % Create figure
    fig = figure('Visible', 'off', 'Units', 'inches', 'Position', [0 0 pw ph], ...
        'PaperPositionMode', 'auto', 'PaperSize', [pw ph]);

    try
        % ==================== PAGE 1: Summary ====================
        renderPage1Summary(fig, report);

        % Add page to PDF
        if exist('exportgraphics', 'file')
            exportgraphics(fig, filepath, 'ContentType', 'vector');
        else
            print(fig, '-dpdf', filepath);
        end

        % ==================== PAGE 2: Visualizations ====================
        if isfield(report, 'images')
            clf(fig);
            renderPage2Visualizations(fig, report);
            if exist('exportgraphics', 'file')
                exportgraphics(fig, filepath, 'ContentType', 'vector', 'Append', true);
            else
                print(fig, '-dpdf', '-append', filepath);
            end
        end

        % ==================== PAGE 3: Evidence Detail ====================
        if isfield(report, 'data') && isfield(report.data, 'evidence')
            clf(fig);
            renderPage3Evidence(fig, report);
            if exist('exportgraphics', 'file')
                exportgraphics(fig, filepath, 'ContentType', 'vector', 'Append', true);
            else
                print(fig, '-dpdf', '-append', filepath);
            end
        end

        close(fig);
        success = exist(filepath, 'file');
    catch ME
        close(fig);
        rethrow(ME);
    end
end

function success = renderReportPNG(report, filepath, params)
%RENDERREPORT_PNG  Render report as single PNG (fallback).

    rc = report_config();
    pw = rc.pageSize(1);
    ph = rc.pageSize(2);

    fig = figure('Visible', 'off', 'Units', 'inches', 'Position', [0 0 pw ph]);
    try
        renderPage1Summary(fig, report);
        if exist('exportgraphics', 'file')
            exportgraphics(fig, filepath, 'Resolution', 300);
        else
            print(fig, '-dpng', '-r300', filepath);
        end
        close(fig);
        success = exist(filepath, 'file');
    catch ME
        close(fig);
        rethrow(ME);
    end
end

function success = renderReportText(report, filepath, params)
%RENDERREPORT_TEXT  Render minimal text report (final fallback).

    fid = fopen(filepath, 'w');
    if fid <= 0
        error('Cannot write report to %s', filepath);
    end

    d = report.data;
    fprintf(fid, '%s\n', '=================================================================');
    fprintf(fid, '%s\n', '                    RETINASENSE SCREENING REPORT');
    fprintf(fid, '%s\n', '=================================================================');
    fprintf(fid, '\n');
    fprintf(fid, 'Patient: %s  |  Eye: %s  |  PHC: %s\n', d.patientId, d.eye, d.phcId);
    fprintf(fid, 'Timestamp: %s\n', d.timestamp);
    fprintf(fid, '\n');
    fprintf(fid, 'Quality: %s (score %.2f)\n', upper(d.quality), d.qualityScore);
    fprintf(fid, '\n');

    if isnan(d.grade) || strcmpi(d.quality, 'ungradable')
        % Ungradable: honest recapture notice, no fabricated grade/referral.
        [qReason, qInstr] = recaptureInfo(d);
        fprintf(fid, 'SCREENING RESULT: IMAGE UNGRADABLE - RECAPTURE REQUESTED\n');
        fprintf(fid, 'Failure reasons: %s\n', qualityFailuresStr(d));
        fprintf(fid, 'Recapture requested (%s): %s\n', qReason, qInstr);
        fprintf(fid, 'No AI grade or referral decision was produced for this image.\n');
        fprintf(fid, '\n');
    else
        fprintf(fid, 'AI DR Grade: %d (%s)  |  Referable: %d  |  Referable Prob: %.3f\n', ...
            d.grade, d.gradeLabel, d.referable, d.referableProb);
        fprintf(fid, 'Calibrated Probs: [%.2f %.2f %.2f %.2f %.2f]\n', d.calibratedProbs);
        fprintf(fid, 'Confidence: %.3f  |  Uncertainty: %.3f\n', d.confidence, d.uncertainty);
        fprintf(fid, '\n');
        fprintf(fid, 'Review Action: %s  |  Grader: %s  |  Status: %s\n', ...
            d.reviewAction, d.reviewGraderId, d.reviewStatus);
        fprintf(fid, 'Final Grade: %d (%s)\n', d.finalGrade, d.finalGradeLabel);
        fprintf(fid, 'Final Referral: %d\n', d.finalReferral);
        fprintf(fid, 'AI Grade Immutable: %d\n', d.aiGradeImmutable);
        fprintf(fid, '\n');
    end
    fprintf(fid, '%s\n', '-----------------------------------------------------------------');
    fprintf(fid, '%s\n', report.summary);
    fprintf(fid, '%s\n', '-----------------------------------------------------------------');
    fprintf(fid, 'DISCLAIMER: %s\n', report.disclaimer);
    fprintf(fid, '%s\n', '=================================================================');
    fclose(fid);
    success = exist(filepath, 'file');
end

function renderPage1Summary(fig, report)
%RENDERPAGE1SUMMARY  Render the first page with case info and DR result.

    d = report.data;
    clf(fig);

    rc = report_config();
    textColor = rc.colors.body;
    sectionColor = rc.colors.section;
    highlightColor = rc.colors.highlight;
    warningColor = rc.colors.warning;
    disclaimerColor = rc.colors.disclaimer;

    % Title
    text(0.5, 0.97, 'RetinaSense Retinal Screening Report', ...
        'FontSize', 18, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'Color', rc.colors.title);
    text(0.5, 0.945, sprintf('Generated: %s', datestr(now, 'yyyy-mm-dd HH:MM:SS')), ...
        'FontSize', 9, 'HorizontalAlignment', 'center', 'Color', disclaimerColor);

    hold on;

    % Layout constants
    xLeft = 0.08;
    xMid = 0.35;
    xRight = 0.58;
    lineH = 0.032;
    sectionGap = 0.018;

    yPos = 0.91;

    % ---- CASE INFORMATION ----
    text(xLeft, yPos, 'CASE INFORMATION', 'FontSize', 12, 'FontWeight', 'bold', 'Color', sectionColor);
    yPos = yPos - lineH;
    info = {
        {'Patient ID:', d.patientId};
        {'Eye:', d.eye};
        {'Timestamp:', d.timestamp};
        {'PHC ID:', d.phcId};
    };
    for i = 1:numel(info)
        text(xLeft, yPos, info{i}{1}, 'FontSize', 10, 'Color', textColor);
        text(xMid, yPos, info{i}{2}, 'FontSize', 10, 'FontWeight', 'bold', 'Color', textColor);
        yPos = yPos - lineH;
    end

    % ---- IMAGE QUALITY ----
    yPos = yPos - sectionGap;
    text(xLeft, yPos, 'IMAGE QUALITY', 'FontSize', 12, 'FontWeight', 'bold', 'Color', sectionColor);
    yPos = yPos - lineH;
    qc = d.quality;
    qm = d.qualityMetrics;
    qColor = textColor;
    if strcmpi(qc, 'ungradable'); qColor = warningColor;
    elseif strcmpi(qc, 'borderline'); qColor = [0.7 0.4 0]; end
    info = {
        {'Overall Quality:', upper(qc), qColor};
        {'Quality Score:', sprintf('%.2f', d.qualityScore), textColor};
        {'Focus:', sprintf('%.2f', qm.focus), textColor};
        {'Illumination:', sprintf('%.2f', qm.illumination), textColor};
        {'FOV Coverage:', sprintf('%.2f', qm.fovCoverage), textColor};
        {'Artifacts:', sprintf('%.2f', qm.artifacts), textColor};
        {'Enhanced:', mat2str(d.enhanced), textColor};
    };
    for i = 1:numel(info)
        text(xLeft, yPos, info{i}{1}, 'FontSize', 10, 'Color', textColor);
        text(xMid, yPos, info{i}{2}, 'FontSize', 10, 'FontWeight', 'bold', 'Color', info{i}{3});
        yPos = yPos - lineH;
    end

    % ---- DR SCREENING RESULT ----
    if isnan(d.grade) || strcmpi(d.quality, 'ungradable')
        % Ungradable: recapture notice; no grade/referral is fabricated.
        yPos = yPos - sectionGap;
        text(xLeft, yPos, 'SCREENING RESULT', 'FontSize', 12, 'FontWeight', 'bold', 'Color', warningColor);
        yPos = yPos - lineH;
        text(xLeft, yPos, 'IMAGE UNGRADABLE  -  RECAPTURE REQUESTED', 'FontSize', 12, ...
            'FontWeight', 'bold', 'Color', [0.8 0 0]);
        yPos = yPos - lineH;
        text(xLeft, yPos, 'Failure reasons:', 'FontSize', 10, 'Color', textColor);
        text(xMid, yPos, qualityFailuresStr(d), 'FontSize', 10, 'FontWeight', 'bold', 'Color', warningColor);
        yPos = yPos - lineH;
        [qReason, qInstr] = recaptureInfo(d);
        text(xLeft, yPos, 'Recapture requested:', 'FontSize', 10, 'Color', textColor);
        text(xMid, yPos, sprintf('(%s)', qReason), 'FontSize', 10, 'FontWeight', 'bold', 'Color', warningColor);
        yPos = yPos - lineH;
        text(xLeft, yPos - 0.01, qInstr, 'FontSize', 10, 'Color', textColor);
        yPos = yPos + lineH;
        yPos = yPos - lineH;
        text(xLeft, yPos, 'No AI grade or referral decision was produced for this image.', ...
            'FontSize', 10, 'FontWeight', 'bold', 'Color', warningColor);
        yPos = yPos - lineH;
    else
    yPos = yPos - sectionGap;
    text(xLeft, yPos, 'DR SCREENING RESULT', 'FontSize', 12, 'FontWeight', 'bold', 'Color', sectionColor);
    yPos = yPos - lineH;

    % AI Grade (original, immutable)
    gradeIdx = d.grade + 1;
    gradeColors = {[0 0.5 0], [0 0.6 0], [0.7 0.4 0], [0.8 0 0], [0.8 0 0]};
    gColor = gradeColors{min(gradeIdx, 5)};

    % Show AI grade and final grade side by side
    aiGradeStr = sprintf('AI DR Grade: %d (%s)', d.grade, d.gradeLabel);
    text(xLeft, yPos, aiGradeStr, 'FontSize', 11, 'FontWeight', 'bold', 'Color', gColor);

    if ~isnan(d.finalGrade) && d.finalGrade ~= d.grade
        % Override: show final grade on same line
        fgIdx = d.finalGrade + 1;
        fgColor = gradeColors{min(fgIdx, 5)};
        overrideStr = sprintf('   >> Final Grade: %d (%s)', d.finalGrade, d.finalGradeLabel);
        text(xLeft + 0.32, yPos, overrideStr, 'FontSize', 11, 'FontWeight', 'bold', 'Color', fgColor);
    end
    yPos = yPos - lineH;

    % Referable
    refStr = 'Not Referable';
    refColor = highlightColor;
    if d.referable; refStr = 'REFERABLE (Level 2+)'; refColor = warningColor; end
    text(xLeft, yPos, 'Referral Status:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, refStr, 'FontSize', 10, 'FontWeight', 'bold', 'Color', refColor);
    yPos = yPos - lineH;

    % Raw probs
    text(xLeft, yPos, 'Raw Probabilities:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, sprintf('[%.2f %.2f %.2f %.2f %.2f]', d.rawProbs), ...
        'FontSize', 10, 'Color', textColor);
    yPos = yPos - lineH;

    % Referable probability
    text(xLeft, yPos, 'Referable Probability:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, sprintf('%.3f', d.referableProb), 'FontSize', 10, 'FontWeight', 'bold', 'Color', textColor);
    yPos = yPos - lineH;

    % ---- CALIBRATION & CONFIDENCE ----
    yPos = yPos - sectionGap;
    text(xLeft, yPos, 'CALIBRATION & CONFIDENCE', 'FontSize', 12, 'FontWeight', 'bold', 'Color', sectionColor);
    yPos = yPos - lineH;

    text(xLeft, yPos, 'Calibrated Probs:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, sprintf('[%.2f %.2f %.2f %.2f %.2f]', d.calibratedProbs), ...
        'FontSize', 10, 'Color', textColor);
    yPos = yPos - lineH;

    text(xLeft, yPos, 'Confidence:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, sprintf('%.3f', d.confidence), 'FontSize', 10, 'FontWeight', 'bold', 'Color', textColor);
    yPos = yPos - lineH;

    text(xLeft, yPos, 'Uncertainty:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, sprintf('%.3f', d.uncertainty), 'FontSize', 10, 'Color', textColor);
    yPos = yPos - lineH;

    revReqStr = 'Not required';
    revReqColor = highlightColor;
    if d.reviewRequired; revReqStr = 'REQUIRED'; revReqColor = warningColor; end
    text(xLeft, yPos, 'Review Required:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, revReqStr, 'FontSize', 10, 'FontWeight', 'bold', 'Color', revReqColor);
    yPos = yPos - lineH;

    % ---- HUMAN REVIEW & FINAL DECISION ----
    yPos = yPos - sectionGap;
    text(xLeft, yPos, 'HUMAN REVIEW & FINAL DECISION', 'FontSize', 12, 'FontWeight', 'bold', 'Color', sectionColor);
    yPos = yPos - lineH;

    text(xLeft, yPos, 'Review Action:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, d.reviewAction, 'FontSize', 10, 'FontWeight', 'bold', 'Color', textColor);
    yPos = yPos - lineH;

    text(xLeft, yPos, 'Grader ID:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, d.reviewGraderId, 'FontSize', 10, 'Color', textColor);
    yPos = yPos - lineH;

    text(xLeft, yPos, 'Review Status:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, d.reviewStatus, 'FontSize', 10, 'FontWeight', 'bold', 'Color', textColor);
    yPos = yPos - lineH;

    % Final referral decision
    frStr = 'No referral';
    frColor = highlightColor;
    if d.finalReferral; frStr = 'FINAL: REFER TO OPHTHALMOLOGIST'; frColor = warningColor; end
    text(xLeft, yPos, 'Final Referral:', 'FontSize', 10, 'Color', textColor);
    text(xMid, yPos, frStr, 'FontSize', 10, 'FontWeight', 'bold', 'Color', frColor);
    yPos = yPos - lineH;

    % AI immutability badge
    if d.aiGradeImmutable
        text(xLeft, yPos, 'AI Grade Immutable:', 'FontSize', 10, 'Color', textColor);
        text(xMid, yPos, 'YES — original AI grading preserved', 'FontSize', 10, ...
            'FontWeight', 'bold', 'Color', [0 0.4 0.7]);
    end
    end

    % ---- DISCLAIMER ----
    yPos = 0.06;
    text(0.08, yPos, 'DISCLAIMER', 'FontSize', 10, 'FontWeight', 'bold', 'Color', warningColor);
    text(0.08, yPos - lineH, report.disclaimer, 'FontSize', 8, 'Color', disclaimerColor);
    text(0.08, yPos - 2*lineH, rc.gradCamNote, 'FontSize', 8, 'Color', disclaimerColor);

    axis off;
    hold off;
end

function renderPage2Visualizations(fig, report)
%RENDERPAGE2VISUALIZATIONS  Render the image visualizations page.
%
%   Shows the working image, the real Grad-CAM attention overlay and the
%   lesion/optic-disc evidence overlay (when each is available). Unavailable
%   panels render as honest gray placeholders - no fabricated attention or
%   evidence is ever drawn (AGENTS.md #3).

    d = report.data;
    clf(fig);
    hold on;

    rc = report_config();
    vs = rc.visuals;
    textColor = rc.colors.body;
    grayColor = [0.5 0.5 0.5];

    % Availability status (content-based, set by buildReport).
    exp = struct('attentionImageAvailable', false, ...
                 'evidenceOverlayAvailable', false, ...
                 'note', '');
    if isfield(d, 'explainability')
        e = d.explainability;
        fields = fieldnames(exp);
        for i = 1:numel(fields)
            if isfield(e, fields{i}); exp.(fields{i}) = e.(fields{i}); end
        end
    end

    imgs = struct('image', [], 'attentionImage', [], 'evidenceOverlay', []);
    if isfield(report, 'images')
        f = fieldnames(imgs);
        for i = 1:numel(f)
            if isfield(report.images, f{i}); imgs.(f{i}) = report.images.(f{i}); end
        end
    end

    % Title
    text(0.5, vs.titleY, 'IMAGE VISUALIZATIONS', ...
        'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
        'Color', rc.colors.title);

    % Honest availability status line.
    if exp.attentionImageAvailable && ~isempty(imgs.attentionImage)
        attnStr = 'Grad-CAM Attention: Available';
        attnCol = rc.colors.highlight;
    else
        attnStr = 'Grad-CAM Attention: Not available (no model attention)';
        attnCol = grayColor;
    end
    if exp.evidenceOverlayAvailable && ~isempty(imgs.evidenceOverlay)
        evStr = 'Evidence Overlay: Available';
        evCol = rc.colors.highlight;
    else
        evStr = 'Evidence Overlay: Not available (no lesion/optic-disc candidates)';
        evCol = grayColor;
    end
    text(0.08, vs.statusY, attnStr, 'FontSize', 11, 'Color', attnCol);
    text(0.46, vs.statusY, evStr, 'FontSize', 11, 'Color', evCol);
    if ~isempty(exp.note)
        text(0.08, vs.noteY, exp.note, 'FontSize', 10, 'Color', [0.5 0 0]);
    end

    % ---- Image panels (real content only; steady layout so a missing panel
    % is visibly honest, never replaced with a fake one) ----
    showOriginal  = ~isempty(imgs.image);
    showAttention = exp.attentionImageAvailable && ~isempty(imgs.attentionImage);
    showEvidence  = exp.evidenceOverlayAvailable && ~isempty(imgs.evidenceOverlay);
    captions = {'Original working image', 'Grad-CAM attention', 'Evidence overlay'};
    content  = {imgs.image, imgs.attentionImage, imgs.evidenceOverlay};
    shown    = [showOriginal, showAttention, showEvidence];

    x = vs.panelStartX;
    for i = 1:3
        rect = [x, vs.rowTop - vs.panelWidth, vs.panelWidth, vs.panelWidth];
        drawVisualPanel(fig, rect, content{i}, captions{i}, shown(i), rc);
        x = x + vs.panelWidth + vs.panelGap;
    end

    % Pipeline stages
    yPos = vs.rowTop - vs.panelWidth - 0.06;
    text(0.08, yPos, 'PIPELINE STAGES EXECUTED', 'FontSize', 12, 'FontWeight', 'bold');
    yPos = yPos - 0.035;
    for i = 1:numel(d.pipelineStages)
        text(0.12, yPos, sprintf('%d. %s', i, d.pipelineStages{i}), 'FontSize', 10, 'Color', textColor);
        yPos = yPos - 0.030;
    end

    axis off;
    hold off;
end

function drawVisualPanel(fig, rect, img, caption, available, rc)
%DRAWVISUALPANEL  Draw one visualization panel (image or honest placeholder).
    ax = axes(fig, 'Units', 'normalized', 'Position', rect);
    cla(ax);
    if available
        image(ax, img);
        axis(ax, 'image');
    else
        patch(ax, [0 1 1 0], [0 0 1 1], [0.95 0.95 0.95], ...
            'EdgeColor', [0.6 0.6 0.6], 'LineWidth', 0.5);
        text(ax, 0.5, 0.5, 'Not available', 'HorizontalAlignment', 'center', ...
            'FontSize', rc.visuals.noteFontSize + 1, 'Color', [0.45 0.45 0.45]);
    end
    ax.XTick = [];
    ax.YTick = [];
    title(ax, caption, 'FontSize', rc.visuals.labelFontSize, 'FontWeight', 'bold');
end

function renderPage3Evidence(fig, report)
%RENDERPAGE3EVIDENCE  Render evidence detail page.

    d = report.data;
    clf(fig);
    hold on;

    text(0.08, 0.95, 'RETINAL STRUCTURE & LESION EVIDENCE', 'FontSize', 16, 'FontWeight', 'bold');

    yPos = 0.90;
    lineH = 0.04;

    if isfield(d, 'evidence')
        ev = d.evidence;

        % Optic Disc
        if isfield(ev, 'opticDisc')
            od = ev.opticDisc;
            text(0.08, yPos, 'Optic Disc', 'FontSize', 13, 'FontWeight', 'bold');
            yPos = yPos - lineH;
            statusStr = 'Not Detected';
            if od.detected
                statusStr = sprintf('Detected (conf=%.2f, %s)', od.confidence, od.status);
            elseif strcmp(od.status, 'low_confidence')
                statusStr = sprintf('Low Confidence (conf=%.2f)', od.confidence);
            end
            info = {
                {'Status:', statusStr};
                {'Center:', arrayToStr(od.center)};
                {'BBox:', arrayToStr(od.bbox)};
                {'Method:', od.method};
            };
            for i = 1:numel(info)
                text(0.12, yPos, info{i}{1}, 'FontSize', 11);
                text(0.35, yPos, info{i}{2}, 'FontSize', 11);
                yPos = yPos - lineH;
            end
            yPos = yPos - lineH;
        end

        % Fovea
        if isfield(ev, 'fovea')
            fv = ev.fovea;
            text(0.08, yPos, 'Fovea', 'FontSize', 13, 'FontWeight', 'bold');
            yPos = yPos - lineH;
            info = {
                {'Status:', ternary(fv.detected, 'Detected', 'Not Detected')};
                {'Center:', arrayToStr(fv.center)};
            };
            for i = 1:numel(info)
                text(0.12, yPos, info{i}{1}, 'FontSize', 11);
                text(0.35, yPos, info{i}{2}, 'FontSize', 11);
                yPos = yPos - lineH;
            end
            yPos = yPos - lineH;
        end

        % Vessels
        if isfield(ev, 'vessels')
            vs = ev.vessels;
            text(0.08, yPos, 'Vessels', 'FontSize', 13, 'FontWeight', 'bold');
            yPos = yPos - lineH;
            info = {
                {'Available:', ternary(vs.available, 'Yes', 'No')};
                {'Density:', sprintf('%.4f', vs.density)};
            };
            for i = 1:numel(info)
                text(0.12, yPos, info{i}{1}, 'FontSize', 11);
                text(0.35, yPos, info{i}{2}, 'FontSize', 11);
                yPos = yPos - lineH;
            end
            yPos = yPos - lineH;
        end

        % Lesions
        if isfield(ev, 'lesions')
            text(0.08, yPos, 'Lesion Candidate Evidence', 'FontSize', 13, 'FontWeight', 'bold');
            yPos = yPos - lineH;
            classes = {'exudates', 'hemorrhages', 'microaneurysms', 'neoVasc'};
            labels = {'Exudates', 'Hemorrhages', 'Microaneurysms', 'NeoVasc'};
            for i = 1:numel(classes)
                cls = classes{i};
                if isfield(ev.lesions, cls)
                    les = ev.lesions.(cls);
                    statusStr = ternary(les.hasCandidates, ...
                        sprintf('%d candidate(s)', les.candidateCount), ...
                        'No candidates');
                    text(0.12, yPos, sprintf('%s: %s', labels{i}, statusStr), 'FontSize', 11);
                    yPos = yPos - lineH;
                end
            end
            yPos = yPos - lineH;
        end

        % Advisory Confidence
        if isfield(ev, 'advisoryConfidence')
            text(0.08, yPos, 'Advisory Evidence Confidence', 'FontSize', 13, 'FontWeight', 'bold');
            yPos = yPos - lineH;
            text(0.12, yPos, sprintf('%s', ev.advisoryConfidence), 'FontSize', 11, 'FontWeight', 'bold');
        end
    end

    axis off;
    hold off;
end

function s = arrayToStr(arr)
    if isempty(arr)
        s = '[]';
    elseif isvector(arr) && numel(arr) <= 4
        s = sprintf('[%s]', strjoin(arrayfun(@(x) sprintf('%.1f', x), arr, 'UniformOutput', false), ', '));
    else
        s = sprintf('[%d x %d]', size(arr,1), size(arr,2));
    end
end

function s = ternary(cond, trueVal, falseVal)
    if cond; s = trueVal; else; s = falseVal; end
end

function [reason, instruction] = recaptureInfo(d)
%RECAPTUREINFO  Recapture reason/instruction from report data ('' if absent).
    reason = '';
    instruction = '';
    if isfield(d, 'recapture')
        if isfield(d.recapture, 'reasonCode')
            reason = d.recapture.reasonCode;
        end
        if isfield(d.recapture, 'instruction')
            instruction = d.recapture.instruction;
        end
    end
end

function s = qualityFailuresStr(d)
%QUALITYFAILURESSTR  Comma-joined quality failure reasons ('n/a' if absent).
    if isfield(d, 'qualityFailures') && ~isempty(d.qualityFailures)
        s = strjoin(d.qualityFailures, ', ');
    else
        s = 'n/a';
    end
end