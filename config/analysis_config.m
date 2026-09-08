function a = analysis_config()
%ANALYSIS_CONFIG  Retinal analysis configuration (config/analysis_config.m).
%
%   a = analysis_config()
%
%   Central configuration for advisory retinal structure analysis (Stage 5).
%   No hard-coded thresholds in module code; everything driven from here.
%
%   References: docs/ARCHITECTURE.md §2 Stage 5, §3.3-3.5, §4.3.

    a = struct();

    % ---- Optic Disc Localization (locateOpticDisc.m) ----
    a.opticDisc = struct( ...
        'method',              'morphology_bright_temporal', ... % 'morphology_bright_temporal' | 'template'
        'greenChannelWeight',  1.0,      ... % weight for green channel (best disc contrast)
        'minDiscDiameterPx',   40,       ... % minimum expected disc diameter in working image
        'maxDiscDiameterPx',   180,      ... % maximum expected disc diameter in working image
        'temporalSideBias',    0.6,      ... % fraction from left: search temporal (right) side for right eye
        'morphology',          struct( ...
            'diskRadius',       15,       ... % structuring element radius for top-hat
            'topHatThreshold',  0.15,     ... % fraction of max for candidate threshold
            'minAreaFraction',  0.001,    ... % min area as fraction of image area
            'maxAreaFraction',  0.03),    ... % max area as fraction of image area
        'circularityThreshold', 0.4,     ... % min circularity (4*pi*area/perimeter^2) for candidates
        'confidenceThresholds', struct( ...
            'high',   0.75,    ... % confidence >= high -> 'high'
            'medium', 0.40),   ... % confidence >= medium -> 'medium', else 'low'
        'fallbackToTemplate',  true);      % if morphology fails, try template matching

    % ---- Vessel Segmentation (segmentVessels.m) ----
    a.vessels = struct( ...
        'method',         'matched_filter', ... % 'matched_filter' | 'unet'
        'scales',         [1 2 3 4],          ... % filter scales
        'threshold',      0.15,               ... % threshold on filter response
        'morphCleanup',   true);

    % ---- Fovea Localization (locateFovea.m) ----
    a.fovea = struct( ...
        'method',              'geometric_from_disc', ... % 'geometric_from_disc' | 'darkest_temporal'
        'discDiameterMultiplier', 1.5,                 ... % fovea ~1.5 disc diameters temporal to disc
        'searchRadiusFraction',   0.3);                ... % search radius as fraction of image diagonal

    % ---- Lesion Detection (detectLesions.m) ----
    a.lesions = struct( ...
        'exudates',   struct('method', 'tophat_bright', 'topHatRadius', 10, 'threshold', 0.20), ...
        'hemorrhages',struct('method', 'dark_blob',     'minArea', 20,   'maxArea', 500, 'threshold', 0.15), ...
        'microaneurysms',struct('method','round_blob',  'minArea', 5,    'maxArea', 50,  'threshold', 0.10), ...
        'neoVasc',    struct('method', 'curvilinear',   'minLength', 30));

    % ---- Advisory confidence aggregation ----
    a.confidence = struct( ...
        'perDetectorWeights', struct( ...
            'vessels',    0.2, ...
            'opticDisc',  0.3, ...
            'fovea',      0.2, ...
            'lesions',    0.3), ...
        'thresholds', struct( ...
            'high',   0.7, ...
            'medium', 0.4));
end