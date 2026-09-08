function vesselMask = segmentVessels(image, params)
%SEGMENTVESSELS  Stage 5a: vessel segmentation map (ADVISORY ONLY).
%
%   vesselMask = segmentVessels(image, params)
%
%   image: HxWx3 uint8 working image
%   params: analysis parameters (may be empty struct in Sprint 0)
%
%   CONTRACT: logical HxW vessel mask. Advisory/non-blocking — grading NEVER
%   depends on this output (docs/ARCHITECTURE.md §3.3).
%
%   TODO(Sprint 7): classical matched-filter + morphology first; optional U-Net
%   ablation on DRIVE later. This Sprint-0 stub returns an all-false mask so the
%   interface is callable without faking results.

    if nargin < 2 || isempty(params); params = struct(); end

    [h, w, ~] = size(image);
    vesselMask = false(h, w);   % honest empty mask: not claiming detections
end