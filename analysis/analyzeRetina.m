function evidence = analyzeRetina(image, fovMask, params)
%ANALYZERETINA  Stage 5 orchestrator: retinal structure + lesion analysis.
%
%   evidence = analyzeRetina(image, fovMask, params)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3). ADVISORY and NON-BLOCKING:
%   failures or empty detections never affect grading, explainability routing
%   or the final referral (except via evidence overlays in the report).
%
%   params may include params.eye ('left'|'right') from Case.meta to
%   orient temporal structures correctly (fovea placement).

    if nargin < 2; fovMask = []; end
    if nargin < 3 || isempty(params) || isempty(fieldnames(params))
        params = analysis_config();
    end

    vesselMask = segmentVessels(image, params.vessels, fovMask);
    opticDisc  = locateOpticDisc(image, params.opticDisc, fovMask);
    
    % Pass eye orientation to fovea localization
    foveaParams = params.fovea;
    if isfield(params, 'eye') && ~isempty(params.eye)
        foveaParams.eye = params.eye;
    end
    fovea      = locateFovea(image, opticDisc, foveaParams);
    
    % Prepare lesion detection params with cross-module info
    lesionParams = params.lesions;
    if ~isempty(fovMask)
        lesionParams.fovMask = fovMask;
    end
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

    % Pass pipeline-customized confidence params so the advisory confidence
    % label always agrees with the thresholds the caller was configured with.
    confidenceParams = [];
    if isfield(params, 'confidence'); confidenceParams = params.confidence; end
    evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions, confidenceParams);
end