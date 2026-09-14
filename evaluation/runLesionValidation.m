function out = runLesionValidation(maxSamples)
%RUNLESIONVALIDATION  IDRiD lesion-detection validation (bounded, honest).
%
%   out = runLesionValidation()                % up to 3 samples
%   out = runLesionValidation(maxSamples)
%
%   Runs the advisory lesion detector (analysis/analyzeRetina.m ->
%   detectLesions.m, the SAME production path) on a BOUNDED subset of IDRiD
%   SEGMENTATION images, and computes per-lesion Dice / IoU / sensitivity /
%   precision against the OFFICIAL IDRiD segmentation masks.
%
%   HONESTY: if no IDRiD data exists, out.status = 'NOT AVAILABLE' with no
%   numbers. Every reported number comes from a real detector run on a real
%   image against an official mask. Empty GT excluded (never negatives).

    if nargin < 1 || isempty(maxSamples); maxSamples = 3; end

    ds = loadDataset('idrid');
    out = struct('dataset', 'idrid_segmentation', 'status', '', 'n', 0, ...
        'maskAvailability', struct(), 'lesions', struct(), ...
        'units', 'working-image pixel maps (max edge 1024, aspect preserved)', ...
        'note', '');

    if isempty(ds.files)
        out.status = 'NOT AVAILABLE';
        out.note   = 'IDRiD data files unavailable.';
        logMessage('warn', 'runLesionValidation', out.note);
        return;
    end

    S = ds.parts.segmentation;
    if S.n == 0
        out.status = 'NOT AVAILABLE';
        out.note = 'IDRiD segmentation part unavailable.';
        logMessage('warn', 'runLesionValidation', out.note);
        return;
    end

    try
        params = analysis_config();
    catch
        params = [];
    end
    if isempty(params)
        out.status = 'FAIL';
        out.note = 'analysis_config() unavailable.';
        logMessage('warn', 'runLesionValidation', out.note);
        return;
    end

    lesionSpec = struct('ma', 'microaneurysms', 'he', 'hemorrhages', 'ex', 'exudates');

    % initialise accumulators
    accMa = metricAccum(); accHe = metricAccum(); accEx = metricAccum();

    idx = spreadAcrossSplits(S.split, maxSamples);
    n = numel(idx);
    sampleCells = cell(n, 1);

    for s = 1:n
        i = idx(s);
        imgNative = imread(S.files{i});
        [~, workingSize] = toWorkingSize(size(imgNative, 2), size(imgNative, 1));
        imgWk = imresize(imgNative, workingSize);
        ev = analyzeRetina(imgWk, [], params);

        smp = struct('image', S.files{i}, 'image_id', char(S.ids(i)), ...
            'split', char(S.split(i)), 'working', workingSize);

        [gt, rec] = evalLesion(ds.root, S.masks.ma{i}, workingSize, ev.lesions.microaneurysms.map);
        smp.ma = rec; accMa = pushMetric(accMa, rec);
        [gt, rec] = evalLesion(ds.root, S.masks.he{i}, workingSize, ev.lesions.hemorrhages.map);
        smp.he = rec; accHe = pushMetric(accHe, rec);
        [gt, rec] = evalLesion(ds.root, S.masks.ex{i}, workingSize, ev.lesions.exudates.map);
        smp.ex = rec; accEx = pushMetric(accEx, rec);

        sampleCells{s} = smp;
    end

    % mask availability
    for f = {'ma', 'he', 'ex', 'se', 'od'}
        cnt = 0;
        for k = 1:S.n
            if ~isempty(S.masks.(f{1}){k})
                p = fullfile(ds.root, S.masks.(f{1}){k});
                if exist(p, 'file') == 2; cnt = cnt + 1; end
            end
        end
        out.maskAvailability.(f{1}) = cnt;
    end

    out.n = n;
    out.status = 'PASS';
    out.note = sprintf('IDRiD: %d seg images analyzed (bounded) at working res.', n);

    out.lesions.ma = finalizeAccum(accMa);
    out.lesions.he = finalizeAccum(accHe);
    out.lesions.ex = finalizeAccum(accEx);
    out.lesions.se = struct('n', 0, 'note', 'GT exists (N=40) but no SE-specific detector class; not scored.');
    out.lesions.neoVasc = struct('n', 0, 'note', 'No official IDRiD GT.');

    % Build samples struct
    out.samples = struct();
    for s = 1:n
        out.samples.(['s' num2str(s)]) = sampleCells{s};
    end

    logMessage('info', 'runLesionValidation', out.note);
end

function [gt, rec] = evalLesion(root, rel, workingSize, pred)
    gt = readMask(root, rel, workingSize);
    pred = logical(pred);
    rec = struct('gtPresent', ~isempty(rel), 'gtNnz', nnz(gt), 'predNnz', nnz(pred), ...
        'dice', nan, 'iou', nan, 'sensitivity', nan, 'precision', nan);
    if nnz(gt) > 0
        tp = nnz(gt & pred);
        rec.dice       = 2 * tp / max(1, nnz(gt) + nnz(pred));
        rec.iou        = tp / max(1, nnz(gt | pred));
        rec.sensitivity = tp / nnz(gt);
        rec.precision  = tp / max(1, nnz(pred));
    end
end

function acc = metricAccum()
    acc = struct('n', 0, 'nGtPresent', 0, 'nEmptyGtExcluded', 0, ...
        'diceSum', 0, 'iouSum', 0, 'sensSum', 0, 'precSum', 0, ...
        'diceMean', nan, 'diceMedian', nan, ...
        'iouMean', nan, 'iouMedian', nan, ...
        'sensitivityMean', nan, 'precisionMean', nan, ...
        'diceVals', [], 'iouVals', [], 'sensVals', [], 'precVals', []);
end

function acc = pushMetric(acc, rec)
    if rec.gtPresent; acc.nGtPresent = acc.nGtPresent + 1; end
    if rec.gtNnz == 0; acc.nEmptyGtExcluded = acc.nEmptyGtExcluded + 1; return; end
    acc.n = acc.n + 1;
    acc.diceVals(end+1) = rec.dice;
    acc.iouVals(end+1)  = rec.iou;
    acc.sensVals(end+1) = rec.sensitivity;
    acc.precVals(end+1) = rec.precision;
end

function acc = finalizeAccum(acc)
    if acc.n == 0; return; end
    acc.diceMean = mean(acc.diceVals);
    acc.diceMedian = median(acc.diceVals);
    acc.iouMean = mean(acc.iouVals);
    acc.iouMedian = median(acc.iouVals);
    acc.sensitivityMean = mean(acc.sensVals);
    acc.precisionMean = mean(acc.precVals);
end

function gt = readMask(root, rel, workingSize)
    if isempty(rel); gt = false(workingSize); return; end
    p = fullfile(root, rel);
    if exist(p, 'file') ~= 2; gt = false(workingSize); return; end
    m = imread(p);
    if ndims(m) == 3; m = m(:, :, 1); end
    m = m > 0;
    if ~isequal(size(m), workingSize)
        m = imresize(double(m), workingSize, 'nearest') > 0.5;
    end
    gt = m;
end

function [scale, workingSize] = toWorkingSize(w, h)
    maxEdge = 1024;
    scale = maxEdge / max(w, h);
    workingSize = [round(h * scale), round(w * scale)];
end

function idx = spreadAcrossSplits(splitCell, maxSamples)
    trainIdx = find(strcmp(splitCell, 'train'));
    testIdx  = find(strcmp(splitCell, 'test'));
    nTr = numel(trainIdx); nTe = numel(testIdx);
    if nTr + nTe == 0
        idx = (1:maxSamples).';
        idx = idx(idx <= numel(splitCell));
        return;
    end
    idx = [];
    if nTr > 0
        take = min(maxSamples, max(1, round(maxSamples * nTr / (nTr + nTe))));
        sel = unique(round(linspace(1, nTr, min(take, nTr))));
        idx = trainIdx(sel); %#ok<AGROW>
    end
    if nTe > 0 && numel(idx) < maxSamples
        take = min(maxSamples - numel(idx), nTe);
        if take > 0
            sel = unique(round(linspace(1, nTe, take)));
            idx = [idx; testIdx(sel)]; %#ok<AGROW>
        end
    end
    idx = unique(idx(:));
end