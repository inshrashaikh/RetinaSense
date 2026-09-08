function evidence = analyzeRetina(image, fovMask, params)
%ANALYZERETINA  Stage 5 orchestrator: retinal structure + lesion analysis.
%
%   evidence = analyzeRetina(image, fovMask, params)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3). ADVISORY and NON-BLOCKING:
%   failures or empty detections never affect grading, explainability routing
%   or the final referral (except via evidence overlays in the report).

    if nargin < 2; fovMask = []; end
    if nargin < 3; params = struct(); end

    vesselMask = segmentVessels(image, params);
    opticDisc  = locateOpticDisc(image, params);
    fovea      = locateFovea(image, params);
    lesions    = detectLesions(image, params);

    evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions);
end