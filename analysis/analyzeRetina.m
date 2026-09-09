function evidence = analyzeRetina(image, fovMask, params)
%ANALYZERETINA  Stage 5 orchestrator: retinal structure + lesion analysis.
%
%   evidence = analyzeRetina(image, fovMask, params)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3). ADVISORY and NON-BLOCKING:
%   failures or empty detections never affect grading, explainability routing
%   or the final referral (except via evidence overlays in the report).

    if nargin < 2; fovMask = []; end
    if nargin < 3 || isempty(params); params = analysis_config(); end

    vesselMask = segmentVessels(image, params.vessels);
    opticDisc  = locateOpticDisc(image, params.opticDisc);
    fovea      = locateFovea(image, opticDisc, params.fovea);
    
    % Prepare lesion detection params with cross-module info
    lesionParams = params.lesions;
    if isstruct(opticDisc) && isfield(opticDisc, 'center') && ~isempty(opticDisc.center)
        lesionParams.opticDiscCenter = opticDisc.center;
        if isfield(opticDisc, 'bbox') && ~isempty(opticDisc.bbox)
            lesionParams.opticDiscRadius = mean([opticDisc.bbox(3), opticDisc.bbox(4)]) / 2;
        end
    end
    lesionParams.vesselMask = vesselMask;
    if ~isempty(fovea) && numel(fovea) >= 2
        lesionParams.foveaCenter = fovea(1:2);
    end
    
    lesions    = detectLesions(image, lesionParams);

    evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions);
end