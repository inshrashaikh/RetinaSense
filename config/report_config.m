function r = report_config()
%REPORT_CONFIG  Reporting configuration (config/report_config.m).
%
%   r = report_config()
%
%   Central configuration for report generation and rendering.
%   No hard-coded layout parameters in module code; everything driven from here.
%
%   References: docs/ARCHITECTURE.md §9, §4.8.

    r = struct();

    % ---- Output ----
    r.format = 'pdf';           % 'pdf' | 'png' | 'txt' | 'auto'
    r.filenameTemplate = 'report_%s'; % %s replaced with timestamp
    r.includeTimestamp = true;

    % ---- Page Layout (inches) ----
    r.pageSize = [8.5, 11];     % US Letter
    r.margins = [0.5, 0.5, 0.5, 0.5]; % left, right, top, bottom

    % ---- Typography ----
    r.titleFontSize = 18;
    r.sectionFontSize = 14;
    r.bodyFontSize = 11;
    r.smallFontSize = 9;
    r.fontName = 'Helvetica';   % fallback: 'DejaVu Sans'

    % ---- Colors (RGB 0-1) ----
    r.colors = struct( ...
        'title',       [0.1, 0.2, 0.4], ...
        'section',     [0.2, 0.3, 0.5], ...
        'body',        [0.1, 0.1, 0.1], ...
        'highlight',   [0.0, 0.5, 0.0], ...
        'warning',     [0.7, 0.0, 0.0], ...
        'disclaimer',  [0.4, 0.4, 0.4], ...
        'background',  [1.0, 1.0, 1.0]);

    % ---- Image Rendering ----
    r.image = struct( ...
        'maxWidthInches',  5.5, ... % max width for image panels
        'maxHeightInches', 4.0, ... % max height for image panels
        'interpolation',   'bilinear', ...
        'showColorbar',    false);

    % ---- Visualization page layout (page 2 PDF) ----
    % Normalized figure coordinates (each axis = one page width/height).
    r.visuals = struct( ...
        'titleY',        0.955, ... % page 2 title baseline
        'statusY',       0.910, ... % availability status line
        'noteY',         0.875, ... % Grad-CAM note line
        'rowTop',        0.840, ... % top of the image panel row
        'panelWidth',    0.260, ... % width of each panel (square panels)
        'panelGap',      0.040, ... % gap between consecutive panels
        'panelStartX',   0.065, ... % x of the first panel
        'labelFontSize', 10, ...    % caption under each panel
        'noteFontSize',  8);        % placeholder / footer text size

    % ---- Content Sections ----
    r.sections = struct( ...
        'caseInfo',       true, ...
        'qualityMetrics', true, ...
        'drResult',       true, ...
        'calibration',    true, ...
        'review',         true, ...
        'explainability', true, ...
        'opticDisc',      true, ...
        'fovea',          true, ...
        'vessels',        true, ...
        'lesions',        true, ...
        'pipelineStages', true, ...
        'disclaimer',     true);

    % ---- Disclaimer ----
    r.disclaimerText = 'Screening decision-support only. Not a diagnosis and not a replacement for an ophthalmologist.';

    % ---- Grad-CAM Note ----
    r.gradCamNote = 'Grad-CAM represents model attention, not proof of causality.';

    % ---- Output Path ----
    % Uses paths().output from config/paths.m
end