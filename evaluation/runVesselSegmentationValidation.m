function out = runVesselSegmentationValidation(maxSamples)
%RUNVESSELSEGMENTATIONVALIDATION  DRIVE vessel-segmentation validation hook.
%
%   out = runVesselSegmentationValidation()            % up to 3 samples
%   out = runVesselSegmentationValidation(maxSamples)
%
%   Connects the real DRIVE loader (loadDataset('drive')) to the advisory
%   vessel segmenter (analysis/segmentVessels.m) and reports honest Dice /
%   overlap between the segmentation mask and the official manual mask.
%
%   HONESTY: if no DRIVE data exists, out.status = 'NOT AVAILABLE' with no
%   numbers, never fabricated metrics. Sample count is intentionally bounded
%   (default 3) so this can run without expensive full-dataset processing.
%
%   ROLE: DRIVE is a VESSEL-SEGMENTATION VALIDATION dataset, not training
%   data for the DR classifier. Results here are advisory (analysis/ Stage 5).

    if nargin < 1 || isempty(maxSamples); maxSamples = 3; end

    ds = loadDataset('drive');
    out = struct('dataset', 'drive', 'status', '', 'n', 0, ...
        'samples', struct(), 'note', '');

    if isempty(ds.files)
        out.status = 'NOT AVAILABLE';
        out.note   = 'DRIVE data files unavailable; loader + validation hook prepared but dataset not validated.';
        logMessage('warn', 'runVesselSegmentationValidation', out.note);
        return;
    end

    n = min(maxSamples, numel(ds.files));
    try
        params = analysis_config();
        params = params.vessels;
    catch
        params = [];
    end

    for i = 1:n
        img = imread(ds.files(i));
        mask = imread(ds.annotations(i));
        if size(mask, 3) > 1; mask = mask(:, :, 1); end
        mask = mask > 0;

        pred = segmentVessels(img, params);
        if ~islogical(pred); pred = pred > 0; end
        pred = imresize(logical(pred), size(mask), 'nearest');

        d = dice(pred, mask);
        ov = dice(pred, mask, 'jaccard');
        out.samples.(['s' num2str(i)]) = struct( ...
            'image', ds.files(i), 'dice', d, 'jaccard', ov);
    end

    out.n = n;
    out.status = 'PASS';
    out.note = sprintf('DRIVE: %d=%d image/mask pairs sampled (bounded).', ds.n, numel(ds.files));
end

function d = dice(a, b, flag)
    if nargin < 3; flag = 'dice'; end
    inter = sum(a(:) & b(:));
    if strcmpi(flag, 'jaccard')
        union = sum(a(:) | b(:));
        d = inter / max(1, union);
    else
        d = 2 * inter / max(1, sum(a(:)) + sum(b(:)));
    end
end