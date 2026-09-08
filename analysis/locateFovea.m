function fovea = locateFovea(image, params)
%LOCATEFOVEA  Stage 5c: fovea location (ADVISORY ONLY).
%
%   fovea = locateFovea(image, params)
%
%   CONTRACT: [x, y] pixel coordinate of fovea, or [] when unknown.
%   Derived geometrically from the disc (~1.5 disc-diam temporal), if known.
%
%   TODO(Sprint 7): geometric derivation after locateOpticDisc
%   (docs/ARCHITECTURE.md §3.5). Sprint 0 returns [] honestly.

    if nargin < 2 || isempty(params); params = struct(); end
    fovea = [];
end