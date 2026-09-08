function opticDisc = locateOpticDisc(image, params)
%LOCATEOPTICDISC  Stage 5b: optic disc location (ADVISORY ONLY).
%
%   opticDisc = locateOpticDisc(image, params)
%
%   CONTRACT: [x, y] pixel coordinate of optic disc centre, or [] when unknown.
%
%   TODO(Sprint 7): bright temporal-side region via morphology + template
%   fallback (docs/ARCHITECTURE.md §3.5). Sprint 0 returns [] honestly.

    if nargin < 2 || isempty(params); params = struct(); end
    opticDisc = [];
end