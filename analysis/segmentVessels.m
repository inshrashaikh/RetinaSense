function vesselMask = segmentVessels(image, params, fovMask)
%SEGMENTVESSELS  Stage 5a: vessel segmentation map (ADVISORY ONLY).
%
%   vesselMask = segmentVessels(image, params)
%   vesselMask = segmentVessels(image, params, fovMask)
%
%   image: HxWx3 uint8 working image (already quality-gated)
%   params: vessel segmentation parameters from config/analysis_config.m
%   fovMask: optional HxW logical field-of-view mask from the quality gate;
%            when omitted, one is derived from the green-channel threshold.
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3):
%     vesselMask: logical HxW vessel mask
%     Advisory/non-blocking — grading NEVER depends on this output.
%
%   Method: Classical matched-filter vessel segmentation.
%   Multi-orientation, multi-scale line detection via 2D Gaussian derivative
%   filters. Config-driven thresholds; no fabricated detections.
%
%   TODO(Sprint 7+): optional U-Net ablation on DRIVE; refine with validated data.

    if nargin < 2 || isempty(params)
        params = analysis_config();
        params = params.vessels;
    end

    % Default honest empty result
    vesselMask = logical([]);

    % Validate input
    if isempty(image) || ndims(image) ~= 3 || size(image, 3) ~= 3
        return;
    end

    [h, w, ~] = size(image);

    % --- Extract green channel (best contrast for vessels) ---
    green = double(image(:,:,2)) / 255.0;

    % --- Create FOV mask if not provided ---
    if nargin >= 3 && islogical(fovMask) && isequal(size(fovMask), [h, w])
        % Caller-provided mask (quality gate) takes precedence.
    else
        fovMask = green > 0.05;
    end
    if nnz(fovMask) < 0.1 * h * w
        return; % insufficient FOV
    end

    % --- Illumination normalization (CLAHE-like local contrast enhancement) ---
    % Use adapthisteq if available, otherwise simple morphological normalization
    try
        % Local contrast enhancement using morphological top-hat
        seIllum = strel('disk', 15);
        greenEnhanced = imtophat(green, seIllum) + green;
        % Also apply bottom-hat for dark structures
        greenEnhanced = greenEnhanced - imbothat(greenEnhanced, seIllum);
    catch
        greenEnhanced = green;
    end

    % Normalize to [0,1]
    greenEnhanced = mat2gray(greenEnhanced);

    % --- Multi-orientation, multi-scale matched filter ---
    % 2D Gaussian derivative (first derivative of Gaussian) filters
    % at multiple orientations and scales
    scales = params.scales;           % e.g., [1 2 3 4]
    numOrientations = 12;             % 12 orientations (15 degree steps)
    
    maxResponse = zeros(h, w, 'single');
    
    for scaleIdx = 1:numel(scales)
        sigma = scales(scaleIdx);
        
        % Generate oriented filters for this scale
        filterSize = round(3 * sigma) * 2 + 1;
        filterSize = max(filterSize, 5);
        
        [fy, fx] = ndgrid(-floor(filterSize/2):floor(filterSize/2));
        r2 = fx.^2 + fy.^2;
        
        for orientIdx = 0:numOrientations-1
            theta = orientIdx * pi / numOrientations;
            % Directional derivative: cos(theta)*d/dx + sin(theta)*d/dy
            % Gaussian derivative kernels
            gx = -fx .* exp(-r2 / (2 * sigma^2)) / (2 * pi * sigma^4);
            gy = -fy .* exp(-r2 / (2 * sigma^2)) / (2 * pi * sigma^4);
            
            % Oriented filter
            orientedFilter = cos(theta) * gx + sin(theta) * gy;
            orientedFilter = orientedFilter - mean(orientedFilter(:)); % zero-mean
            
            % Apply filter
            try
                response = imfilter(greenEnhanced, orientedFilter, 'conv', 'replicate');
                response = abs(response); % magnitude response
                maxResponse = max(maxResponse, single(response));
            catch
                % Skip failed filter
            end
        end
    end

    % --- Threshold vessel response ---
    threshold = params.threshold; % config-driven
    % Adaptive: use percentile of response within FOV
    fovResponse = maxResponse(fovMask);
    if numel(fovResponse) > 100
        adaptiveThresh = max(threshold, prctile(fovResponse, 95));
    else
        adaptiveThresh = threshold;
    end
    
    vesselMask = maxResponse >= adaptiveThresh;
    
    % --- Morphological cleanup ---
    if params.morphCleanup
        % Remove small isolated pixels
        vesselMask = bwareaopen(vesselMask, 10);
        % Close small gaps
        vesselMask = imclose(vesselMask, strel('disk', 1));
        % Remove very thin spurs
        vesselMask = bwmorph(vesselMask, 'spur', 2);
    end
    
    % --- Restrict to FOV ---
    vesselMask = vesselMask & fovMask;
    
    % Ensure logical output
    vesselMask = logical(vesselMask);
end