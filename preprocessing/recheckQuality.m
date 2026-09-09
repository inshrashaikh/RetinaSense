function [ok, recheckQualityOut, enhMeta] = recheckQuality(enhanced, enhMeta, preScore)
%RECHECKQUALITY  Stage 4: re-run the quality gate on the enhanced image.
%
%   [ok, recheckQualityOut, enhMeta] = recheckQuality(enhanced, enhMeta)
%   [ok, recheckQualityOut, enhMeta] = recheckQuality(enhanced, enhMeta, preScore)
%
%   enhanced: HxWx3 uint8 enhanced image from enhanceImage
%   enhMeta:  enhancement metadata (appended with recheck result)
%   preScore: pre-enhancement quality score (from Stage 1), used to set
%             enhMeta.improved = recheck score > preScore. If omitted,
%             improved is left as reported by enhanceImage (false).
%
%   CONTRACT (docs/ARCHITECTURE.md §2 Stage 4):
%     ok                 true  -> pass to analysis/grading
%                        false -> route to recapture (still ungradable)
%     recheckQualityOut  full quality struct from assessQuality on enhanced
%     enhMeta.recheckClass  quality class after recheck
%     enhMeta.improved      true if recheck score > pre-enhancement score
%
%   Uses the SAME scorer as Stage 1 (single source of truth for the gate).

    recheckQualityOut = assessQuality(enhanced);

    enhMeta.recheckClass = recheckQualityOut.class;

    if nargin >= 3 && ~isempty(preScore)
        enhMeta.improved = recheckQualityOut.score > preScore;
    end

    if strcmp(recheckQualityOut.class, 'ungradable')
        ok = false;
    else
        ok = true;
    end
end