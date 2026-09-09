function lesions = detectLesions(image, params)
%DETECTLESIONS  Stage 5d: high-recall lesion candidate detection (ADVISORY).
%
%   lesions = detectLesions(image, params)
%
%   image: HxWx3 uint8 working image (already quality-gated)
%   params: lesion detection parameters from config/analysis_config.m
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3): struct per lesion class:
%     exudates / hemorrhages / microaneurysms / neoVasc
%       .map      logical candidate map
%       .count    double
%       .features double x N  (area, roundness, intensity contrast, distToFovea)
%
%   Posture is deliberately HIGH-RECALL / LOW-PRECISION evidence; must never be
%   presented as diagnostic certainty. Sub-pixel MA/neovascularization detection
%   must not be claimed without evidence (docs/ARCHITECTURE.md §3.4).
%
%   Method: Classical CV candidate detectors:
%     Exudates     - morphological top-hat on green channel (bright lesions)
%     Hemorrhages  - dark blob detection on green channel (dark lesions)
%     Microaneurysms - small round blob detection on green channel
%     NeoVasc      - vessel morphology analysis (abnormal density/branching)
%
%   Advisory: never blocks grading. Returns honest empty results if detection fails.
%
%   TODO(Sprint 7+): refine with validated datasets; add supervised classifiers.

    if nargin < 2 || isempty(params)
        params = analysis_config();
        params = params.lesions;
    end

    % Default honest empty result
    classes = {'exudates', 'hemorrhages', 'microaneurysms', 'neoVasc'};
    lesions = struct();
    
    % Validate input
    if isempty(image) || ndims(image) ~= 3 || size(image, 3) ~= 3
        [h, w, ~] = size(image);
        emptyF = zeros(4, 0);
        for i = 1:numel(classes)
            lesions.(classes{i}) = struct( ...
                'map',      false(h, w), ...
                'count',    0, ...
                'features', emptyF);
        end
        return;
    end

    [h, w, ~] = size(image);
    emptyF = zeros(4, 0);

    % --- Extract green channel (best contrast for most lesions) ---
    green = double(image(:,:,2)) / 255.0;

    % --- Create FOV mask (exclude dark background) ---
    fovMask = green > 0.05;
    if nnz(fovMask) < 0.1 * h * w
        % Insufficient FOV - return empty
        for i = 1:numel(classes)
            lesions.(classes{i}) = struct( ...
                'map',      false(h, w), ...
                'count',    0, ...
                'features', emptyF);
        end
        return;
    end

    % --- Illumination normalization ---
    try
        seIllum = strel('disk', 15);
        greenNorm = imtophat(green, seIllum) + green;
        greenNorm = greenNorm - imbothat(greenNorm, seIllum);
        greenNorm = mat2gray(greenNorm);
    catch
        greenNorm = green;
    end

    % --- Get optic disc info for suppression (passed via params or global) ---
    % We'll check if opticDisc info is available in params
    discCenter = [];
    discRadius = 0;
    if isfield(params, 'opticDiscCenter') && ~isempty(params.opticDiscCenter)
        discCenter = params.opticDiscCenter;
        if isfield(params, 'opticDiscRadius')
            discRadius = params.opticDiscRadius;
        else
            discRadius = 50; % default
        end
    end

    % --- Get vessel mask for integration ---
    vesselMask = false(h, w);
    if isfield(params, 'vesselMask') && islogical(params.vesselMask)
        vesselMask = params.vesselMask;
    end

    % --- Get fovea location for distance features ---
    foveaCenter = [];
    if isfield(params, 'foveaCenter') && ~isempty(params.foveaCenter)
        foveaCenter = params.foveaCenter;
    end

    % ============================================================
    % EXUDATES: Bright lesions via top-hat
    % ============================================================
    pEx = params.exudates;
    seRadius = pEx.topHatRadius;
    se = strel('disk', seRadius);
    
    % Top-hat enhances bright structures smaller than structuring element
    topHatEx = imtophat(greenNorm, se);
    
    % Threshold
    maxVal = max(topHatEx(fovMask));
    if maxVal > 0
        thresh = pEx.threshold * maxVal;
        candidates = topHatEx > thresh;
        candidates = candidates & fovMask;
        
        % Suppress optic disc region (bright but not exudate)
        if ~isempty(discCenter) && discRadius > 0
            [yy, xx] = ndgrid(1:h, 1:w);
            discMask = sqrt((xx - discCenter(1)).^2 + (yy - discCenter(2)).^2) <= discRadius * 1.2;
            candidates = candidates & ~discMask;
        end
        
        % Cleanup
        candidates = imopen(candidates, strel('disk', 1));
        candidates = imclose(candidates, strel('disk', 2));
        candidates = bwareaopen(candidates, 5);
        
        % Connected components and features
        [lesions.exudates.map, lesions.exudates.count, lesions.exudates.features] = ...
            extractLesionFeatures(candidates, greenNorm, foveaCenter, h, w);
    else
        lesions.exudates.map = false(h, w);
        lesions.exudates.count = 0;
        lesions.exudates.features = emptyF;
    end

    % ============================================================
    % HEMORRHAGES: Dark lesions via bottom-hat / dark blob detection
    % ============================================================
    pHem = params.hemorrhages;
    
    % Bottom-hat enhances dark structures
    seHem = strel('disk', 8);
    botHatHem = imbothat(greenNorm, seHem);
    
    % Also consider dark regions in original green
    % Combine: dark in both bottom-hat and original
    darkRegions = greenNorm < (pHem.threshold * mean(greenNorm(fovMask)));
    candidatesHem = botHatHem > (pHem.threshold * max(botHatHem(fovMask)));
    candidatesHem = candidatesHem & darkRegions & fovMask;
    
    % Remove vessel pixels (hemorrhages are typically not on major vessels)
    if nnz(vesselMask) > 0
        candidatesHem = candidatesHem & ~imdilate(vesselMask, strel('disk', 2));
    end
    
    % Suppress optic disc region
    if ~isempty(discCenter) && discRadius > 0
        [yy, xx] = ndgrid(1:h, 1:w);
        discMask = sqrt((xx - discCenter(1)).^2 + (yy - discCenter(2)).^2) <= discRadius * 1.2;
        candidatesHem = candidatesHem & ~discMask;
    end
    
    % Size filtering
    candidatesHem = bwareaopen(candidatesHem, pHem.minArea);
    % Upper bound on area
    cc = bwconncomp(candidatesHem);
    if cc.NumObjects > 0
        stats = regionprops(cc, 'Area', 'PixelIdxList');
        for i = 1:cc.NumObjects
            if stats(i).Area > pHem.maxArea
                candidatesHem(stats(i).PixelIdxList) = false;
            end
        end
    end
    
    % Morphological cleanup
    candidatesHem = imopen(candidatesHem, strel('disk', 1));
    candidatesHem = imclose(candidatesHem, strel('disk', 2));
    
    [lesions.hemorrhages.map, lesions.hemorrhages.count, lesions.hemorrhages.features] = ...
        extractLesionFeatures(candidatesHem, greenNorm, foveaCenter, h, w);

    % ============================================================
    % MICROANEURYSMS: Small round dark blobs
    % ============================================================
    pMA = params.microaneurysms;
    
    % Use small structuring element for top-hat on inverted (dark blobs)
    % Or use Laplacian of Gaussian for blob detection
    % Simple approach: dark small round structures
    seMA = strel('disk', 2);
    botHatMA = imbothat(greenNorm, seMA);
    
    maxVal = max(botHatMA(fovMask));
    if maxVal > 0
        candidatesMA = botHatMA > (pMA.threshold * maxVal);
        candidatesMA = candidatesMA & fovMask;
        
        % Remove vessel pixels (MA often on vessels but we want distinct candidates)
        if nnz(vesselMask) > 0
            candidatesMA = candidatesMA & ~imdilate(vesselMask, strel('disk', 1));
        end
        
        % Suppress optic disc
        if ~isempty(discCenter) && discRadius > 0
            [yy, xx] = ndgrid(1:h, 1:w);
            discMask = sqrt((xx - discCenter(1)).^2 + (yy - discCenter(2)).^2) <= discRadius * 1.2;
            candidatesMA = candidatesMA & ~discMask;
        end
        
        % Size filtering - very small
        candidatesMA = bwareaopen(candidatesMA, pMA.minArea);
        cc = bwconncomp(candidatesMA);
        if cc.NumObjects > 0
            stats = regionprops(cc, 'Area', 'PixelIdxList');
            for i = 1:cc.NumObjects
                if stats(i).Area > pMA.maxArea
                    candidatesMA(stats(i).PixelIdxList) = false;
                end
            end
        end
        
        % Roundness filtering - keep only round-ish
        candidatesMA = imopen(candidatesMA, strel('disk', 1));
        
        [lesions.microaneurysms.map, lesions.microaneurysms.count, lesions.microaneurysms.features] = ...
            extractLesionFeatures(candidatesMA, greenNorm, foveaCenter, h, w);
    else
        lesions.microaneurysms.map = false(h, w);
        lesions.microaneurysms.count = 0;
        lesions.microaneurysms.features = emptyF;
    end

    % ============================================================
    % NEOVASC: Vessel morphology abnormality evidence
    % ============================================================
    pNV = params.neoVasc;
    
    if nnz(vesselMask) > 0
        % Analyze vessel mask for abnormal patterns
        % High local vessel density, branching points, abnormal curvature
        
        % Local vessel density
        seDense = strel('disk', 10);
        vesselDensity = imfilter(single(vesselMask), single(seDense.getnhood()), 'conv', 'replicate');
        
        % Find high-density regions not explained by normal vessels
        % Threshold at high percentile
        fovDensity = vesselDensity(fovMask);
        if numel(fovDensity) > 100
            densityThresh = prctile(fovDensity, 95);
            candidatesNV = vesselDensity > densityThresh;
            candidatesNV = candidatesNV & fovMask;
            
            % Remove known normal vessel structures (main arcades)
            % Simple approach: remove regions that are just thick vessels
            candidatesNV = candidatesNV & ~imdilate(vesselMask, strel('disk', 3));
            
            % Suppress optic disc (high vessel density there)
            if ~isempty(discCenter) && discRadius > 0
                [yy, xx] = ndgrid(1:h, 1:w);
                discMask = sqrt((xx - discCenter(1)).^2 + (yy - discCenter(2)).^2) <= discRadius * 1.5;
                candidatesNV = candidatesNV & ~discMask;
            end
            
            % Minimum size
            candidatesNV = bwareaopen(candidatesNV, 20);
            
            [lesions.neoVasc.map, lesions.neoVasc.count, lesions.neoVasc.features] = ...
                extractLesionFeatures(candidatesNV, greenNorm, foveaCenter, h, w);
        else
            lesions.neoVasc.map = false(h, w);
            lesions.neoVasc.count = 0;
            lesions.neoVasc.features = emptyF;
        end
    else
        lesions.neoVasc.map = false(h, w);
        lesions.neoVasc.count = 0;
        lesions.neoVasc.features = emptyF;
    end

end

function [lesionMap, lesionCount, lesionFeatures] = extractLesionFeatures(candidateMap, intensityImage, foveaCenter, h, w)
%EXTRACTLESIONFEATURES  Extract features from connected components.
%
%   candidateMap: logical mask of candidates
%   intensityImage: HxW double [0,1] for intensity features
%   foveaCenter: [x,y] or [] for distance-to-fovea feature
%
%   Returns: map, count, features(4 x N) where features are:
%     row 1: area (pixels)
%     row 2: roundness (4*pi*area/perimeter^2)
%     row 3: mean intensity contrast (vs local background)
%     row 4: distance to fovea (pixels), NaN if fovea unknown

    if ~any(candidateMap(:))
        lesionMap = candidateMap;
        lesionCount = 0;
        lesionFeatures = zeros(4, 0);
        return;
    end

    cc = bwconncomp(candidateMap);
    lesionCount = cc.NumObjects;
    lesionMap = candidateMap;
    
    if lesionCount == 0
        lesionFeatures = zeros(4, 0);
        return;
    end

    stats = regionprops(cc, 'Area', 'Perimeter', 'Centroid', 'PixelIdxList', ...
        'MajorAxisLength', 'MinorAxisLength', 'Eccentricity', 'BoundingBox');

    features = zeros(4, lesionCount);
    
    for i = 1:lesionCount
        area = stats(i).Area;
        perimeter = stats(i).Perimeter;
        centroid = stats(i).Centroid;
        pixelIdx = stats(i).PixelIdxList;
        
        % Feature 1: Area
        features(1, i) = area;
        
        % Feature 2: Roundness (circularity)
        if perimeter > 0
            features(2, i) = 4 * pi * area / (perimeter^2);
        else
            features(2, i) = NaN;
        end
        
        % Feature 3: Intensity contrast (mean lesion intensity vs local background)
        if ~isempty(pixelIdx)
            lesionIntensity = mean(intensityImage(pixelIdx));
            % Local background: dilated region minus lesion
            localMask = false(h, w);
            localMask(pixelIdx) = true;
            localDilated = imdilate(localMask, strel('disk', 3));
            bgMask = localDilated & ~localMask;
            if nnz(bgMask) > 0
                bgIntensity = mean(intensityImage(bgMask));
                features(3, i) = lesionIntensity - bgIntensity;
            else
                features(3, i) = lesionIntensity;
            end
        else
            features(3, i) = NaN;
        end
        
        % Feature 4: Distance to fovea
        if ~isempty(foveaCenter) && numel(foveaCenter) >= 2
            features(4, i) = sqrt((centroid(1) - foveaCenter(1))^2 + ...
                                  (centroid(2) - foveaCenter(2))^2);
        else
            features(4, i) = NaN;
        end
    end
    
    lesionFeatures = features;
end