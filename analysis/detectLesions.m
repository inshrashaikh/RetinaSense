function lesions = detectLesions(image, params)
%DETECTLESIONS  Stage 5d: high-recall lesion candidate detection (ADVISORY).
%
%   lesions = detectLesions(image, params)
%
%   Contract (docs/ARCHITECTURE.md §4.3): struct per lesion class:
%     exudates / hemorrhages / microaneurysms / neoVasc
%       .map      logical candidate map
%       .count    double
%       .features double x N  (area, roundness, intensity contrast, distToFovea)
%
%   Posture is deliberately HIGH-RECALL / LOW-PRECISION evidence; must never be
%   presented as diagnostic certainty. Sub-pixel MA/neovascularization detection
%   must not be claimed without evidence (docs/ARCHITECTURE.md §3.4).
%
%   TODO(Sprint 7): top-hat + threshold for exudates, dark-blob for hemorrhages,
%   small-round-blob for MA. Sprint 0 returns empty, honest candidates.

    if nargin < 2 || isempty(params); params = struct(); end

    classes = {'exudates', 'hemorrhages', 'microaneurysms', 'neoVasc'};
    lesions = struct();
    [h, w, ~] = size(image);
    emptyF = zeros(4, 0);
    for i = 1:numel(classes)
        lesions.(classes{i}) = struct( ...
            'map',      false(h, w), ...   % honest empty candidate map
            'count',    0, ...
            'features', emptyF);
    end
end