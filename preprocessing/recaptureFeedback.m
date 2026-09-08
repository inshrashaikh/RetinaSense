function rec = recaptureFeedback(failureReasons)
%RECAPTUREFEEDBACK  Stage 2: map failing metrics to actionable recapture advice.
%
%   rec = recaptureFeedback(failureReasons)
%
%   failureReasons: cellstr of metric keys (subset of {focus, illumination,
%                    fovCoverage, artifacts})
%
%   CONTRACT (docs/ARCHITECTURE.md §4.1 / §2 Stage 2):
%     rec.reasonCode   string  stable code for the dominant failure
%     rec.instruction  string  human instruction for the field operator
%
%   First-class differentiator: the gate does not just reject, it tells the
%   operator HOW to take a better photo.
%
%   TODO(Sprint 1): validate instruction applicability in field demo
%   (docs/ARCHITECTURE.md §2 Stage 2 metric).

    guide = struct( ...
        'focus', struct('code', 'REFOCUS', ...
            'instruction', 'Image is out of focus. Ask patient to hold still and refocus on the optic disc.'), ...
        'illumination', struct('code', 'FIX_LIGHTING', ...
            'instruction', 'Adjust illumination: avoid under/over exposure, center the light beam.'), ...
        'fovCoverage', struct('code', 'RECENTER_FOV', ...
            'instruction', 'Optic disc not fully visible. Recenter the field of view on the macula-disc axis.'), ...
        'artifacts', struct('code', 'CLEAR_ARTIFACTS', ...
            'instruction', 'Glare/saturation/clipping detected. Reduce flash intensity and ask patient to blink.'));

    if isempty(failureReasons)
        rec = struct('reasonCode', '', 'instruction', '');
        return;
    end

    % Deterministic priority: pick the first reason from a fixed precedence.
    precedence = {'focus', 'illumination', 'fovCoverage', 'artifacts'};
    key = '';
    for i = 1:numel(precedence)
        if any(strcmp(failureReasons, precedence{i}))
            key = precedence{i};
            break;
        end
    end
    if isempty(key); key = failureReasons{1}; end

    g = guide.(key);
    rec = struct('reasonCode', g.code, 'instruction', g.instruction);
end