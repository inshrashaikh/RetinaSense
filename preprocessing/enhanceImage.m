function [enhanced, enhMeta] = enhanceImage(borderlineImage, quality, params)
%ENHANCEIMAGE  Stage 3: adaptive enhancement for borderline images.
%
%   [enhanced, enhMeta] = enhanceImage(borderlineImage, quality, params)
%
%   borderlineImage: HxWx3 uint8 working image classified 'borderline'
%   quality:        quality struct from assessQuality (drives parameter choice)
%   params:         enhancement config (cfg.preprocess.enhance)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.2):
%     enhanced  HxWx3 uint8
%     enhMeta   struct: appliedOps {clahe,illumNorm,denoise}, paramsPerOp,
%               improved (bool), recheckClass
%
%   Architecture: CLAHE + illumination normalization + denoising, parameterized
%   per failing metric (§2 Stage 3). This pre-model build performs the CLAHE and
%   denoise plumbing on the actual pixels; 'improved' and 'recheckClass' are set
%   by the caller's re-check (Stage 4) and filled here as placeholders.
%
%   TODO(Sprint 1): select ops per failure metric and verify no-harm on a
%   borderline subset (docs/ARCHITECTURE.md §2 Stage 3 metric).

    if nargin < 3; params = preprocess_config().enhance; end

    enhMeta = struct( ...
        'appliedOps',    {{}}, ...
        'paramsPerOp',   struct(), ...
        'improved',      false, ...
        'recheckClass',  '');   % filled by the Stage-4 recheck

    enhanced = im2uint8(borderlineImage);

    % ---- CLAHE on the HSV value channel (keeps color intact) ----
    try
        hsv   = rgb2hsv(im2double(enhanced));
        V     = adapthisteq(im2uint8(hsv(:, :, 3)), ...
                     'NumTiles',    params.clahe.numTiles, ...
                     'ClipLimit',   params.clahe.clipLimit, ...
                     'Distribution', params.clahe.distribution);
        hsv(:, :, 3) = im2double(V);
        enhanced = im2uint8(hsv2rgb(hsv));
        enhMeta.appliedOps{end+1} = 'clahe';
        enhMeta.paramsPerOp.clahe = params.clahe;
    catch
        % CLAHE toolbox missing or failed: keep original pixels, note it.
        enhanced = im2uint8(borderlineImage);
        enhMeta.paramsPerOp.claheFailed = true;
    end

    % ---- Illumination normalization (gamma) ----
    if params.applyIllum
        g = params.illumNorm.gamma;
        enhanced = im2uint8(imadjust(im2double(enhanced), [], [], g));
        enhMeta.appliedOps{end+1} = 'illumNorm';
        enhMeta.paramsPerOp.illumNorm = params.illumNorm;
    end

    % ---- Denoising ----
    if params.applyDenoise
        switch params.denoise.method
            case 'median'
                % medfilt2 is 2-D only; apply per-channel for RGB input.
                for ch = 1:size(enhanced, 3)
                    enhanced(:,:,ch) = medfilt2(enhanced(:,:,ch), params.denoise.medSize);
                end
            case 'guided'
                % imguidedfilter may not be present in all toolboxes; fall back.
                try
                    enhanced = imguidedfilter(im2double(enhanced), ...
                        'NeighborhoodSize', 2*[params.denoise.guidedR params.denoise.guidedR], ...
                        'DegreeOfSmoothing', params.denoise.guidedEps);
                catch
                    enhanced = imgaussfilt(im2double(enhanced), params.denoise.sigma);
                end
            otherwise   % 'gaussian'
                enhanced = imgaussfilt(im2double(enhanced), params.denoise.sigma);
        end
        enhanced = im2uint8(enhanced);
        enhMeta.appliedOps{end+1} = 'denoise';
        enhMeta.paramsPerOp.denoise = params.denoise;
    end

    % Flag for recheck: caller sets improved/recheckClass via recheckQuality.
end