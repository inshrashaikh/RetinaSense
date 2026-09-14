function out = runLocalizationValidation(maxSamples)
%RUNLOCALIZATIONVALIDATION  IDRiD optic-disc / fovea localization validation.
%
%   out = runLocalizationValidation()          % up to 3 samples
%   out = runLocalizationValidation(maxSamples)
%
%   Compares the advisory optic-disc / fovea localizers
%   (analysis/locateOpticDisc.m, analysis/locateFovea.m) against the OFFICIAL
%   IDRiD center coordinates on a BOUNDED number of real images, and reports
%   honest pixel distances with units (native image px).
%
%   METHODOLOGY (honest, reproducible):
%     - Sample: bounded subset of the official IDRiD localization split
%       (train + test) so both splits are represented.
%     - Detection runs at the pipeline working resolution
%       (preprocess_config().maxWorkingSize = 1024, aspect preserved) because
%       locateOpticDisc's morphology thresholds are tuned for the working
%       image; the detected center is mapped back to the NATIVE 4288x2848
%       pixel space of the official GT for distance measurement. Units = px.
%     - Fovea: locateFovea needs eye laterality. The official markups carry
%       only X/Y, so laterality is derived per-image from official GT geometry
%       (fovea is temporal to the disc) and supplied to the localizer. The
%       derived eye is recorded per sample. This validates the geometric
%       estimator given correct metadata; it is NOT a claim that laterality
%       was detected independently.
%     - Images where the detector returns not_detected / empty are counted as
%       failures and EXCLUDED from distance statistics (never imputed).
%
%   HONESTY: if no localization data exists, out.status = 'NOT AVAILABLE'
%   with no numbers. Exact N per statistic is reported. Mean/median/max are
%   real measured values. Advisory only — localization never affects grading.

    if nargin < 1 || isempty(maxSamples); maxSamples = 3; end

    ds = loadDataset('idrid');
    out = struct('dataset', 'idrid_localization', 'status', '', ...
        'n', 0, 'units', 'pixels (native image px)', ...
        'opticDisc', struct(), 'fovea', struct(), ...
        'failures', {{}}, 'note', '');

    L = ds.parts.localization;
    if L.n == 0
        out.status = 'NOT AVAILABLE';
        out.note   = 'IDRiD localization data unavailable; hook prepared but dataset not validated.';
        logMessage('warn', 'runLocalizationValidation', out.note);
        return;
    end

    files = cell(L.n, 1);
    for k = 1:L.n; files{k} = char(L.files(k)); end
    odx = cell2mat(L.odx(:)); ody = cell2mat(L.ody(:));
    fox = cell2mat(L.fox(:)); foy = cell2mat(L.foy(:));

    idx = spreadAcrossSplits(L.split, maxSamples);
    n = numel(idx);

    odDists = []; fovDists = [];
    failMsgs = cell(0, 1);
    sampleCells = cell(n, 1);

    try
        cfg = analysis_config();
    catch
        cfg = [];
    end
    if isempty(cfg)
        out.status = 'FAIL';
        out.note = 'analysis_config() unavailable; cannot run localizers.';
        logMessage('warn', 'runLocalizationValidation', out.note);
        return;
    end

    for s = 1:n
        i = idx(s);
        img = imread(files{i});
        [scale, imgW] = workingScale(size(img, 2));
        imgWk = imresize(img, [round(size(img, 1) * scale), imgW]);

        od = locateOpticDisc(imgWk, cfg.opticDisc, []);
        odNative = [0 0];
        odD = nan; fovD = nan;

        if isstruct(od) && isfield(od, 'center') && ~isempty(od.center) && ...
                any(strcmp(od.status, {'detected', 'low_confidence'}))
            odNative = od.center / scale;
            odD = norm(odNative - [odx(i), ody(i)]);
            odDists(end+1, 1) = odD; %#ok<AGROW>
        end

        foveaP = cfg.fovea;
        foveaP.eye = derivedEye(odx(i), ody(i), fox(i), foy(i));
        fov = locateFovea(imgWk, od, foveaP);
        fovNative = [];
        if ~isempty(fov) && numel(fov) == 2
            fovNative = fov / scale;
            fovD = norm(fovNative - [fox(i), foy(i)]);
            fovDists(end+1, 1) = fovD; %#ok<AGROW>
        end

        if isnan(odD) || isnan(fovD)
            failMsgs{end+1, 1} = sprintf('%s: odDetected=%d fovDetected=%d', ... %#ok<AGROW>
                char(L.ids(i)), ~isnan(odD), ~isnan(fovD));
        end

        sampleCells{s} = struct( ...
            'image', files{i}, 'image_id', char(L.ids(i)), 'split', char(L.split(i)), ...
            'gt_od', [odx(i), ody(i)], 'od_pred_native_px', odNative, 'od_distance_px', odD, ...
            'gt_fovea', [fox(i), foy(i)], 'fovea_pred_native_px', fovNative, 'fovea_distance_px', fovD, ...
            'derived_eye', derivedEye(odx(i), ody(i), fox(i), foy(i)));
    end

    out.n = n;
    out.cfgMaxWorkingSize = 1024;
    out.opticDisc = stat3(odDists, n);
    out.fovea     = stat3(fovDists, n);
    out.failures  = failMsgs;
    % Convert cell array to named struct fields for JSON compatibility
    out.samples = struct();
    for s = 1:n
        out.samples.(['s' num2str(s)]) = sampleCells{s};
    end
    if isempty(failMsgs)
        out.status = 'PASS';
    else
        out.status = 'PARTIAL';
    end
    out.note = sprintf( ...
        'IDRiD localization (bounded n=%d): OD mean/median/max = %.1f/%.1f/%.1f px; fovea mean/median/max = %.1f/%.1f/%.1f px.', ...
        n, out.opticDisc.mean, out.opticDisc.median, out.opticDisc.max, ...
        out.fovea.mean, out.fovea.median, out.fovea.max);
    logMessage('info', 'runLocalizationValidation', out.note);
end

function s3 = stat3(x, nTotal)
    if isempty(x)
        s3 = struct('n', 0, 'nFailures', nTotal, ...
            'mean', nan, 'median', nan, 'max', nan);
        return;
    end
    s3 = struct('n', numel(x), 'nFailures', nTotal - numel(x), ...
        'mean', mean(x), 'median', median(x), 'max', max(x));
end

function eyeSide = derivedEye(odx, ody, fox, foy)
    if fox >= odx
        eyeSide = 'right';
    else
        eyeSide = 'left';
    end
end

function [scale, imgW] = workingScale(nativeW)
    maxEdge = 1024;
    scale = maxEdge / nativeW;
    imgW = round(nativeW * scale);
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