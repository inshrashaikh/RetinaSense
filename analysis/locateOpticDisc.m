function result = locateOpticDisc(image, params, fovMask)
%LOCATEOPTICDISC  Stage 5b: optic disc localization (ADVISORY ONLY).
%
%   result = locateOpticDisc(image, params)
%   result = locateOpticDisc(image, params, fovMask)
%
%   image: HxWx3 uint8 working image (already quality-gated)
%   params: analysis parameters from config/analysis_config.m
%   fovMask: optional HxW logical field-of-view mask from the quality gate;
%            when omitted, one is derived from the green-channel threshold.
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3):
%     result.center       [x, y] pixel coordinate of optic disc centre, or [] if not detected
%     result.bbox         [x, y, w, h] bounding box of detected disc region, or []
%     result.confidence   double 0..1 detection confidence
%     result.status       'detected' | 'low_confidence' | 'not_detected'
%     result.method       string describing the method used
%     result.note         string with advisory note
%
%   Method: Classical CV - bright temporal-side region via morphology +
%   connected component analysis with size/circularity constraints.
%   Fallback: template matching if morphology fails.
%
%   Advisory: never blocks grading. Low confidence or not_detected status
%   is returned honestly without faking detections.
%
%   TODO(Sprint 7+): refine with validated datasets; add U-Net ablation.

    if nargin < 2 || isempty(params)
        params = analysis_config();
    end
    if isfield(params, 'opticDisc')
        p = params.opticDisc;
    else
        p = params;   % already the opticDisc sub-struct (analyzeRetina/test call)
    end

    % Default honest empty result
    result = struct( ...
        'center', [], ...
        'bbox', [], ...
        'confidence', 0.0, ...
        'status', 'not_detected', ...
        'method', p.method, ...
        'note', 'Optic disc localization is advisory evidence only; not a diagnosis.');

    % Validate input
    if isempty(image) || ndims(image) ~= 3 || size(image, 3) ~= 3
        result.note = [result.note, ' Invalid input image.'];
        return;
    end

    [h, w, ~] = size(image);

    % --- Extract green channel (best contrast for optic disc) ---
    green = double(image(:,:,2)) / 255.0;

    % --- Create FOV mask (exclude dark background) ---
    if nargin >= 3 && islogical(fovMask) && isequal(size(fovMask), [h, w])
        % Caller-provided mask (quality gate) takes precedence.
    else
        fovMask = green > 0.05;
    end
    if nnz(fovMask) < 0.1 * h * w
        result.note = [result.note, ' Insufficient FOV coverage.'];
        return;
    end

    % --- Morphological top-hat to enhance bright structures ---
    seRadius = p.morphology.diskRadius;
    se = strel('disk', seRadius);
    topHat = imtophat(green, se);

    % --- Threshold to find bright candidates ---
    maxVal = max(topHat(fovMask));
    if maxVal <= 0
        result.note = [result.note, ' No bright structures found in FOV.'];
        % Try template fallback if enabled
        if p.fallbackToTemplate
            result = tryTemplateFallback(green, fovMask, p, result);
        end
        return;
    end

    thresh = p.morphology.topHatThreshold * maxVal;
    candidates = topHat > thresh;
    candidates = candidates & fovMask;

    % --- Clean up with morphology ---
    candidates = imopen(candidates, strel('disk', 3));
    candidates = imclose(candidates, strel('disk', 5));
    candidates = imfill(candidates, 'holes');

    % --- Connected component analysis ---
    cc = bwconncomp(candidates);
    numComponents = cc.NumObjects;

    if numComponents == 0
        result.note = [result.note, ' No connected components after cleanup.'];
        if p.fallbackToTemplate
            result = tryTemplateFallback(green, fovMask, p, result);
        end
        return;
    end

    % --- Compute properties for each component ---
    stats = regionprops(cc, 'Area', 'Centroid', 'BoundingBox', 'Perimeter', 'MajorAxisLength', 'MinorAxisLength', 'Eccentricity', 'Image');

    % --- Filter by size constraints ---
    imgArea = h * w;
    minArea = p.morphology.minAreaFraction * imgArea;
    maxArea = p.morphology.maxAreaFraction * imgArea;

    validIndices = [];
    for i = 1:numComponents
        area = stats(i).Area;
        if area >= minArea && area <= maxArea
            validIndices = [validIndices, i];
        end
    end

    if isempty(validIndices)
        result.note = [result.note, ' No components within expected disc size range.'];
        if p.fallbackToTemplate
            result = tryTemplateFallback(green, fovMask, p, result);
        end
        return;
    end

    % --- Filter by circularity ---
    circularIndices = [];
    for idx = validIndices
        area = stats(idx).Area;
        perimeter = stats(idx).Perimeter;
        if perimeter > 0
            circularity = 4 * pi * area / (perimeter^2);
            if circularity >= p.circularityThreshold
                circularIndices = [circularIndices, idx];
            end
        end
    end

    if isempty(circularIndices)
        result.note = [result.note, ' No components with sufficient circularity.'];
        if p.fallbackToTemplate
            result = tryTemplateFallback(green, fovMask, p, result);
        end
        return;
    end

    % --- Apply temporal side bias ---
    % For right eye: disc is on the right (temporal) side
    % For left eye: disc is on the left (temporal) side
    % We'll bias toward the temporal side based on image width
    temporalBias = p.temporalSideBias; % 0.6 means favor right 60% of image
    temporalX = round(w * temporalBias);

    % Score candidates: brightness + temporal proximity + circularity + size appropriateness
    bestScore = -inf;
    bestIdx = -1;

    for idx = circularIndices
        centroid = stats(idx).Centroid;
        bbox = stats(idx).BoundingBox;
        area = stats(idx).Area;
        perimeter = stats(idx).Perimeter;
        circularity = 4 * pi * area / (perimeter^2);

        % Mean brightness in candidate region
        mask = stats(idx).Image;
        [cy, cx] = find(mask);
        if ~isempty(cx)
            globalX = cx + bbox(1) - 1;
            globalY = cy + bbox(2) - 1;
            brightness = mean(green(sub2ind([h, w], round(globalY), round(globalX))));
        else
            brightness = 0;
        end

        % Temporal proximity score (higher = closer to expected temporal side)
        temporalScore = 1 - abs(centroid(1) - temporalX) / w;

        % Size score: prefer areas in the middle of expected range
        idealArea = (minArea + maxArea) / 2;
        sizeScore = 1 - min(1, abs(area - idealArea) / idealArea);

        % Circularity score
        circScore = circularity;

        % Combined score (weights from config)
        sw = p.scoringWeights;
        score = sw.brightness * brightness + sw.temporal * temporalScore + ...
                sw.size * sizeScore + sw.circularity * circScore;

        if score > bestScore
            bestScore = score;
            bestIdx = idx;
        end
    end

    if bestIdx < 0
        result.note = [result.note, ' No suitable candidate after scoring.'];
        if p.fallbackToTemplate
            result = tryTemplateFallback(green, fovMask, p, result);
        end
        return;
    end

    % --- Build result ---
    centroid = stats(bestIdx).Centroid;
    bbox = stats(bestIdx).BoundingBox;

    result.center = [centroid(1), centroid(2)];
    result.bbox = [bbox(1), bbox(2), bbox(3), bbox(4)];
    result.confidence = min(1.0, max(0.0, bestScore));
    result.method = 'morphology_bright_temporal';

    % Determine status from confidence
    if result.confidence >= p.confidenceThresholds.high
        result.status = 'detected';
    elseif result.confidence >= p.confidenceThresholds.medium
        result.status = 'low_confidence';
    else
        result.status = 'not_detected';
        result.center = [];
        result.bbox = [];
    end

    result.note = sprintf('%s Method: %s. Confidence: %.2f. Status: %s.', ...
        result.note, result.method, result.confidence, result.status);

    % Template fallback if result is not confident and fallback enabled
    if strcmp(result.status, 'not_detected') && p.fallbackToTemplate
        result = tryTemplateFallback(green, fovMask, p, result);
    end
end

function result = tryTemplateFallback(green, fovMask, p, result)
%TRYTEMPLATEFALLBACK  Template matching fallback for optic disc.
    % Simple template: circular bright disk
    [h, w] = size(green);
    
    % Create a disc template at expected size
    templateRadius = round((p.minDiscDiameterPx + p.maxDiscDiameterPx) / 4);
    templateRadius = max(10, min(templateRadius, min(h, w) / 4));
    
    [ty, tx] = ndgrid(-templateRadius:templateRadius);
    template = double(sqrt(tx.^2 + ty.^2) <= templateRadius);
    template = template / sum(template(:)); % normalize
    
    % Normalized cross-correlation on green channel
    % Use only FOV region for efficiency
    fovGreen = green .* double(fovMask);
    
    try
        corr = normxcorr2(template, fovGreen);
        
        % normxcorr2 returns (h+2R) x (w+2R); crop valid region
        validCorr = corr(templateRadius+1:templateRadius+h, templateRadius+1:templateRadius+w);
        
        % Find peak in correlation, constrained to FOV
        validCorr(~fovMask) = -inf;
        [maxCorr, linearIdx] = max(validCorr(:));
        [py, px] = ind2sub(size(validCorr), linearIdx);
        
        % Adjust for template offset: validCorr is cropped to image size, so
        % (px, py) already point at the template center in image coordinates.
        centerX = px;
        centerY = py;
        
        % Check bounds
        if centerX > 0 && centerX <= w && centerY > 0 && centerY <= h
            % Estimate confidence from correlation peak
            conf = max(0, min(1, (maxCorr + 1) / 2)); % NCC is [-1, 1]
            
            if conf > result.confidence
                result.center = [centerX, centerY];
                result.bbox = [centerX - templateRadius, centerY - templateRadius, 2*templateRadius, 2*templateRadius];
                result.confidence = conf;
                result.method = 'template_fallback';
                
                if conf >= p.confidenceThresholds.high
                    result.status = 'detected';
                elseif conf >= p.confidenceThresholds.medium
                    result.status = 'low_confidence';
                else
                    result.status = 'not_detected';
                    result.center = [];
                    result.bbox = [];
                end
                
                result.note = sprintf('%s Template fallback used. Confidence: %.2f. Status: %s.', ...
                    result.note, result.confidence, result.status);
            end
        end
    catch
        % Template fallback failed silently
        result.note = [result.note, ' Template fallback failed.'];
    end
end