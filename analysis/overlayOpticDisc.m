function overlay = overlayOpticDisc(image, opticDiscDetail, options)
%OVERLAYOPTICDISC  Create visualization overlay for optic disc localization.
%
%   overlay = overlayOpticDisc(image, opticDiscDetail, options)
%
%   image: HxWx3 uint8 original retinal image
%   opticDiscDetail: struct from locateOpticDisc (with center, bbox, confidence, status)
%   options: optional struct with fields:
%     - showCenter: boolean (default true)
%     - showBBox: boolean (default true)
%     - showConfidence: boolean (default true)
%     - centerColor: [R G B] uint8 (default [0 255 0] green)
%     - bboxColor: [R G B] uint8 (default [255 255 0] yellow)
%     - textColor: [R G B] uint8 (default [255 255 255] white)
%     - lineWidth: scalar (default 2)
%     - centerRadius: scalar (default 8)
%
%   Returns: HxWx3 uint8 overlay image with optic disc visualization.
%
%   Advisory: this is for evidence visualization only, not diagnostic.

    if nargin < 3 || isempty(options)
        options = struct();
    end

    % Default options
    defaults = struct( ...
        'showCenter',      true, ...
        'showBBox',        true, ...
        'showConfidence',  true, ...
        'centerColor',     uint8([0, 255, 0]), ...
        'bboxColor',       uint8([255, 255, 0]), ...
        'textColor',       uint8([255, 255, 255]), ...
        'lineWidth',       2, ...
        'centerRadius',    8);
    
    opt = defaults;
    for f = fieldnames(defaults)'
        fn = f{1};
        if isfield(options, fn)
            opt.(fn) = options.(fn);
        end
    end

    % Validate input
    if isempty(image) || ndims(image) ~= 3 || size(image, 3) ~= 3
        overlay = image;
        return;
    end

    overlay = image;

    % If no valid detection, return original with status text
    if ~isstruct(opticDiscDetail) || isempty(opticDiscDetail.center) || ...
            ~strcmp(opticDiscDetail.status, 'detected')
        % Add status text
        statusText = 'Optic Disc: ';
        if isstruct(opticDiscDetail) && isfield(opticDiscDetail, 'status')
            statusText = [statusText, opticDiscDetail.status];
        else
            statusText = [statusText, 'not_detected'];
        end
        if isstruct(opticDiscDetail) && isfield(opticDiscDetail, 'confidence')
            statusText = sprintf('%s (conf=%.2f)', statusText, opticDiscDetail.confidence);
        end
        overlay = insertText(overlay, [10, 30], statusText, ...
            'FontSize', 16, 'TextColor', opt.textColor, 'BoxColor', uint8([0,0,0]), 'BoxOpacity', 0.7);
        return;
    end

    center = opticDiscDetail.center;
    bbox = opticDiscDetail.bbox;
    conf = opticDiscDetail.confidence;

    % --- Draw bounding box ---
    if opt.showBBox && ~isempty(bbox) && numel(bbox) >= 4
        x = bbox(1);
        y = bbox(2);
        w = bbox(3);
        h = bbox(4);
        
        % Draw rectangle using line segments
        pts = [x, y; x+w, y; x+w, y+h; x, y+h; x, y];
        overlay = insertShape(overlay, 'Polygon', pts, ...
            'Color', opt.bboxColor, 'LineWidth', opt.lineWidth, 'Opacity', 0.8);
    end

    % --- Draw center crosshair ---
    if opt.showCenter && ~isempty(center) && numel(center) >= 2
        cx = round(center(1));
        cy = round(center(2));
        r = opt.centerRadius;
        
        % Crosshair lines
        line1 = [cx-r, cy; cx+r, cy];
        line2 = [cx, cy-r; cx, cy+r];
        overlay = insertShape(overlay, 'Line', [line1; line2], ...
            'Color', opt.centerColor, 'LineWidth', opt.lineWidth, 'Opacity', 0.9);
        
        % Center circle
        overlay = insertShape(overlay, 'Circle', [cx, cy, r], ...
            'Color', opt.centerColor, 'LineWidth', opt.lineWidth, 'Opacity', 0.7);
    end

    % --- Add confidence/status text ---
    if opt.showConfidence
        statusText = sprintf('Optic Disc: %s (conf=%.2f)', opticDiscDetail.status, conf);
        textPos = [10, 30];
        if ~isempty(center) && center(2) < 50
            textPos = [10, min(size(image,1)-10, center(2) + 30)];
        end
        overlay = insertText(overlay, textPos, statusText, ...
            'FontSize', 16, 'TextColor', opt.textColor, 'BoxColor', uint8([0,0,0]), 'BoxOpacity', 0.7);
    end

    % --- Add method info ---
    if isfield(opticDiscDetail, 'method') && ~isempty(opticDiscDetail.method)
        methodText = sprintf('Method: %s', opticDiscDetail.method);
        overlay = insertText(overlay, [10, 55], methodText, ...
            'FontSize', 12, 'TextColor', opt.textColor, 'BoxColor', uint8([0,0,0]), 'BoxOpacity', 0.7);
    end
end