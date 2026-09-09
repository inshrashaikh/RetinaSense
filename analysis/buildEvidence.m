function evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions, params)
%BUILDEVIDENCE  Stage 5e: assemble the advisory evidence struct.
%
%   evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions)
%   evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions, params)
%
%   params: optional confidence aggregation params (analysis_config()
%   §confidence); when omitted, they are auto-loaded.
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3):
%     evidence.vesselMask  logical
%     evidence.opticDisc   [x,y] | []
%     evidence.fovea       [x,y] | []
%     evidence.lesions     per-class structs
%     evidence.confidence  'low' | 'medium' | 'high'
%     evidence.opticDiscDetail  struct (optional, full localization result)
%
%   confidence encodes advisory certainty of the detections. Sprint 0 stubs
%   return empty detections => confidence 'low' (honest), and analysis NEVER
%   blocks grading.

    % Extract optic disc center for contract compliance [x,y] | []
    if isstruct(opticDisc) && isfield(opticDisc, 'center') && ~isempty(opticDisc.center)
        opticDiscCenter = opticDisc.center;
        opticDiscDetail = opticDisc; % keep full detail for visualization/reporting
    else
        opticDiscCenter = [];
        opticDiscDetail = struct('center', [], 'bbox', [], 'confidence', 0, 'status', 'not_detected', 'method', '', 'note', '');
    end

    % Extract fovea center for contract compliance [x,y] | []
    if ~isempty(fovea) && numel(fovea) >= 2
        foveaCenter = fovea(1:2);
    else
        foveaCenter = [];
    end

    % --- Advisory confidence aggregation ---
    % Weight per detector based on whether it produced a valid result
    if nargin < 5 || isempty(params)
        cfg = analysis_config();
        params = cfg.confidence;
    end
    w = params.perDetectorWeights;
    t = params.thresholds;

    hasVessels = ~isempty(vesselMask) && nnz(vesselMask) > 0;
    hasDisc = ~isempty(opticDiscCenter);
    hasFovea = ~isempty(foveaCenter);
    hasLesions = isstruct(lesions) && ...
        (lesions.exudates.count > 0 || lesions.hemorrhages.count > 0 || ...
         lesions.microaneurysms.count > 0 || lesions.neoVasc.count > 0);

    detectorScores = [hasVessels, hasDisc, hasFovea, hasLesions];
    weights = [w.vessels, w.opticDisc, w.fovea, w.lesions];
    totalScore = sum(detectorScores .* weights);

    if totalScore >= t.high
        confidence = 'high';
    elseif totalScore >= t.medium
        confidence = 'medium';
    else
        confidence = 'low';
    end

    evidence = struct( ...
        'vesselMask', vesselMask, ...
        'opticDisc',  opticDiscCenter, ...
        'fovea',      foveaCenter, ...
        'lesions',    lesions, ...
        'confidence', confidence, ...
        'opticDiscDetail', opticDiscDetail);
end