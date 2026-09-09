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
        if isfield(report, 'data') && isfield(report.data, 'explainability')
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

    fprintf(fid, '%s\n', '=================================================================');
    fprintf(fid, '%s\n', '                    RETINASENSE SCREENING REPORT');
    fprintf(fid, '%s\n', '=================================================================');
    fprintf(fid, '\n');
    fprintf(fid, '%s\n', report.summary);
    fprintf(fid, '\n');
    fprintf(fid, '%s\n', '-----------------------------------------------------------------');
    fprintf(fid, 'DISCLAIMER: %s\n', report.disclaimer);
    fprintf(fid, '%s\n', '-----------------------------------------------------------------');
    fclose(fid);
    success = exist(filepath, 'file');
end

function renderPage1Summary(fig, report)
%RENDERPAGE1SUMMARY  Render the first page with case info and DR result.

    d = report.data;
    clf(fig);

    % Title
    titleStr = 'RetinaSense Retinal Screening Report';
    title(titleStr, 'FontSize', 18, 'FontWeight', 'bold');
    hold on;

    % --- Case Information ---
    yPos = 0.85;
    lineH = 0.045;
    xLeft = 0.08;
    xRight = 0.55;

    text(xLeft, yPos, 'CASE INFORMATION', 'FontSize', 14, 'FontWeight', 'bold');
    yPos = yPos - lineH;
    info = {
        {'Patient ID:', d.patientId};
        {'Eye:', d.eye};
        {'Timestamp:', d.timestamp};
        {'PHC ID:', d.phcId};
    };
    for i = 1:numel(info)
        text(xLeft, yPos, info{i}{1}, 'FontSize', 11);
        text(xRight, yPos, info{i}{2}, 'FontSize', 11, 'FontWeight', 'bold');
        yPos = yPos - lineH;
    end

    yPos = yPos - lineH;
    text(xLeft, yPos, 'IMAGE QUALITY', 'FontSize', 14, 'FontWeight', 'bold');
    yPos = yPos - lineH;
    qc = d.quality;
    qm = d.qualityMetrics;
    info = {
        {'Overall Quality:', qc};
        {'Quality Score:', sprintf('%.2f', d.qualityScore)};
        {'Focus:', sprintf('%.2f', qm.focus)};
        {'Illumination:', sprintf('%.2f', qm.illumination)};
        {'FOV Coverage:', sprintf('%.2f', qm.fovCoverage)};
        {'Artifacts:', sprintf('%.2f', qm.artifacts)};
        {'Enhanced:', d.enhanced};
    };
    for i = 1:numel(info)
        text(xLeft, yPos, info{i}{1}, 'FontSize', 11);
        text(xRight, yPos, info{i}{2}, 'FontSize', 11);
        yPos = yPos - lineH;
    end

    % --- DR Grading ---
    yPos = yPos - lineH;
    text(xLeft, yPos, 'DR SCREENING RESULT', 'FontSize', 14, 'FontWeight', 'bold');
    yPos = yPos - lineH;
    refStr = 'Not Referable';
    if d.referable; refStr = 'Referable (Level 2+)'; end
    info = {
        {'AI DR Grade:', sprintf('%d (%s)', d.grade, d.gradeLabel)};
        {'Referable:', refStr};
        {'Referable Probability:', sprintf('%.3f', d.referableProb)};
        {'Raw Probabilities:', sprintf('[%.2f %.2f %.2f %.2f %.2f]', d.rawProbs)};
    };
    for i = 1:numel(info)
        text(xLeft, yPos, info{i}{1}, 'FontSize', 11);
        text(xRight, yPos, info{i}{2}, 'FontSize', 11);
        yPos = yPos - lineH;
    end

    % --- Calibration & Confidence ---
    yPos = yPos - lineH;
    text(xLeft, yPos, 'CALIBRATION & CONFIDENCE', 'FontSize', 14, 'FontWeight', 'bold');
    yPos = yPos - lineH;
    info = {
        {'Calibrated Confidence:', sprintf('%.3f', d.confidence)};
        {'Uncertainty:', sprintf('%.3f', d.uncertainty)};
        {'Review Required:', d.reviewRequired};
    };
    for i = 1:numel(info)
        text(xLeft, yPos, info{i}{1}, 'FontSize', 11);
        text(xRight, yPos, info{i}{2}, 'FontSize', 11);
        yPos = yPos - lineH;
    end

    % --- Human Review ---
    yPos = yPos - lineH;
    text(xLeft, yPos, 'HUMAN REVIEW', 'FontSize', 14, 'FontWeight', 'bold');
    yPos = yPos - lineH;
    info = {
        {'Review Action:', d.reviewAction};
        {'Grader ID:', d.reviewGraderId};
        {'Review Status:', d.reviewStatus};
        {'Final Referral:', d.finalReferral};
    };
    for i = 1:numel(info)
        text(xLeft, yPos, info{i}{1}, 'FontSize', 11);
        text(xRight, yPos, info{i}{2}, 'FontSize', 11);
        yPos = yPos - lineH;
    end

    % --- Disclaimer ---
    yPos = yPos - 2*lineH;
    disclaimer = report.disclaimer;
    text(0.08, yPos, 'DISCLAIMER', 'FontSize', 12, 'FontWeight', 'bold');
    yPos = yPos - lineH;
    text(0.08, yPos, disclaimer, 'FontSize', 9, 'Color', [0.4 0.4 0.4]);

    axis off;
    hold off;
end

function renderPage2Visualizations(fig, report)
%RENDERPAGE2VISUALIZATIONS  Render image visualizations page.

    d = report.data;
    clf(fig);
    hold on;

    text(0.08, 0.95, 'IMAGE VISUALIZATIONS', 'FontSize', 16, 'FontWeight', 'bold');

    % We need the original image from the case - but we don't have it in report
    % This is a placeholder for when the case image is available
    % In practice, the case image would be passed or stored in report
    
    % Show explainability if available
    if isfield(d, 'explainability') && d.explainability.attentionImageAvailable
        % Grad-CAM and evidence overlay would be shown here
        % For now, indicate availability
        text(0.08, 0.85, 'Grad-CAM Attention: Available', 'FontSize', 11, 'Color', [0, 0.5, 0]);
        text(0.08, 0.80, 'Evidence Overlay: Available', 'FontSize', 11, 'Color', [0, 0.5, 0]);
        text(0.08, 0.75, 'Note: Grad-CAM represents model attention, not causality.', 'FontSize', 10, 'Color', [0.5, 0, 0]);
    else
        text(0.08, 0.85, 'Grad-CAM Attention: Not available (no trained model)', 'FontSize', 11, 'Color', [0.5, 0.5, 0]);
        text(0.08, 0.80, 'Evidence Overlay: Not available', 'FontSize', 11, 'Color', [0.5, 0.5, 0]);
    end

    % Pipeline stages
    yPos = 0.65;
    text(0.08, yPos, 'PIPELINE STAGES EXECUTED', 'FontSize', 14, 'FontWeight', 'bold');
    yPos = yPos - 0.04;
    for i = 1:numel(d.pipelineStages)
        text(0.12, yPos, sprintf('%d. %s', i, d.pipelineStages{i}), 'FontSize', 11);
        yPos = yPos - 0.035;
    end

    axis off;
    hold off;
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