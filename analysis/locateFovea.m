function fovea = locateFovea(image, opticDisc, params)
%LOCATEFOVEA  Stage 5c: fovea location (ADVISORY ONLY).
%
%   fovea = locateFovea(image, opticDisc, params)
%
%   opticDisc: struct with .center [x,y] and .status from locateOpticDisc
%   params: fovea parameters from config/analysis_config.m
%
%   CONTRACT: [x, y] pixel coordinate of fovea, or [] when unknown.
%   Derived geometrically from the disc (~1.5 disc-diam temporal), if known.
%   Fallback: darkest region in temporal search area.
%
%   Advisory: never blocks grading. Returns [] honestly when unknown.

    if nargin < 3 || isempty(params)
        params = analysis_config();
        params = params.fovea;
    end

    fovea = [];

    if isempty(image) || ndims(image) ~= 3 || size(image, 3) ~= 3
        return;
    end

    [h, w, ~] = size(image);

    % --- If optic disc is known, derive fovea geometrically ---
    if isstruct(opticDisc) && ~isempty(opticDisc.center) && ...
            strcmp(opticDisc.status, 'detected')
        discCenter = opticDisc.center;
        discDiameter = mean([opticDisc.bbox(3), opticDisc.bbox(4)]); % approximate
        
        % Fovea is temporal to disc (right for right eye, left for left eye)
        % For now assume right eye (temporal = right side)
        temporalOffset = params.discDiameterMultiplier * discDiameter;
        foveaX = discCenter(1) + temporalOffset;
        foveaY = discCenter(2); % roughly same vertical level
        
        % Constrain to image bounds with margin
        margin = round(min(h, w) * params.searchRadiusFraction);
        foveaX = max(margin, min(w - margin, round(foveaX)));
        foveaY = max(margin, min(h - margin, round(foveaY)));
        
        fovea = [foveaX, foveaY];
        return;
    end

    % --- Fallback: darkest region in temporal search area ---
    % Use green channel (good for fovea contrast)
    green = double(image(:,:,2)) / 255.0;
    
    % Create FOV mask
    fovMask = green > 0.05;
    
    % Search in temporal region (right 2/3 for right eye)
    searchMask = false(h, w);
    temporalStart = round(w / 3);
    searchMask(:, temporalStart:end) = true;
    searchMask = searchMask & fovMask;
    
    if nnz(searchMask) < 100
        return; % insufficient search area
    end
    
    % Apply Gaussian smoothing to find dark blob
    smoothed = imgaussfilt(green, 3);
    smoothed(~searchMask) = 1; % set non-search to bright
    
    % Find darkest point
    [minVal, linearIdx] = min(smoothed(:));
    [fy, fx] = ind2sub([h, w], linearIdx);
    
    % Verify it's actually dark (not just background)
    if minVal < 0.3
        fovea = [fx, fy];
    end
end