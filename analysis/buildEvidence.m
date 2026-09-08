function evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions)
%BUILDEVIDENCE  Stage 5e: assemble the advisory evidence struct.
%
%   evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions)
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
    hasVessels = ~isempty(vesselMask) && nnz(vesselMask) > 0;
    hasDisc = ~isempty(opticDiscCenter);
    hasFovea = ~isempty(foveaCenter);
    hasLesions = isstruct(lesions) && ...
        (lesions.exudates.count > 0 || lesions.hemorrhages.count > 0 || ...
         lesions.microaneurysms.count > 0 || lesions.neoVasc.count > 0);

    % Simple scoring: each detector contributes if it has a result
    % In future, use per-detector confidence scores
    detectorScores = [hasVessels, hasDisc, hasFovea, hasLesions];
    weights = [0.2, 0.3, 0.2, 0.3]; % vessels, disc, fovea, lesions
    totalScore = sum(detectorScores .* weights);

    if totalScore >= 0.7
        confidence = 'high';
    elseif totalScore >= 0.4
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