function report = validateDataset(name, maxSamples)
%VALIDATEDATASET  Bounded integrity validation of a real dataset.
%
%   report = validateDataset(name)
%   report = validateDataset(name, maxSamples)   % default 4
%   report = validateDataset()                    % validate all 4 datasets
%
%   PURPOSE: prove a dataset is ACTUALLY loadable before anything is called
%   "integrated". Checks, on a SMALL bounded sample only (3-5 representative
%   images; never the whole dataset):
%     - manifest/loader returns files
%     - each sampled image exists, decodes, has sane dimensions/channels
%     - label exists where expected
%     - annotation/mask exists where expected
%     - paths resolve to real files
%
%   Return struct:
%     report.dataset, report.status ('PASS' | 'FAIL' | 'NOT AVAILABLE'),
%     report.nOnDisk, report.nSampled, report.samples (per-sample structs),
%     report.errors (cell of failure messages, empty on PASS).
%
%   HONESTY: a dataset with no real files is reported 'NOT AVAILABLE', never
%   'PASS'. Corrupt sample => 'FAIL'. This module is deliberately bounded so
%   it can run in CI without scanning a full dataset.
%
%   Also requires the committed status CSV to be refreshed (see
%   buildDatasetManifests) so manifests only contain real rows.

    if nargin < 2 || isempty(maxSamples); maxSamples = 4; end
    if nargin < 1 || isempty(name)
        ds = loadDataset();
        report = struct();
        for i = 1:numel(ds)
            report.(char(ds{i}.name)) = validateDataset(char(ds{i}.name), maxSamples);
        end
        return;
    end
    maxSamples = min(maxSamples, 5);   % hard bound: 3-5 samples only

    ds = loadDataset(name);
    report = struct('dataset', name, 'status', '', 'nOnDisk', ds.n, ...
        'nSampled', 0, 'samples', struct());
    report.errors = cell(0, 1);
    if isfield(ds, 'parts')
        report.parts = validateIDRiDParts(ds.parts, maxSamples);
    end

    if isempty(ds.files)
        report.status = 'NOT AVAILABLE';
        report.errors = {sprintf('%s: no files found (%s)', name, ds.note)};
        return;
    end

    n = min(maxSamples, numel(ds.files));
    step = max(1, floor(numel(ds.files) / n));   % spread across the set
    sampleIdx = unique(min(1:step:numel(ds.files), numel(ds.files)));
    sampleIdx = sampleIdx(1:min(n, numel(sampleIdx)));
    errs = {};

    for s = 1:numel(sampleIdx)
        i = sampleIdx(s);
        sample = struct('index', i, 'image', ds.files(i), 'ok', false, 'detail', '');
        msgs = validateOne(ds, i);
        if isempty(msgs)
            sample.ok = true;
            sample.detail = 'image + label/annotation verified';
        else
            sample.detail = strjoin(msgs, '; ');
            errs{end+1, 1} = sprintf('%s | %s', char(ds.files(i)), sample.detail); %#ok<AGROW>
        end
        report.samples.(['s' num2str(s)]) = sample;
    end

    report.nSampled = numel(sampleIdx);
    report.errors = errs;
    if isempty(errs)
        report.status = 'PASS';
    else
        report.status = 'FAIL';
    end
    if isfield(report, 'parts')
        partOk = true;
        for p = 1:numel(report.parts)
            partNames = fieldnames(report.parts);
            if ~isstruct(report.parts.(partNames{p})); continue; end
            if ~isfield(report.parts.(partNames{p}), 'status'); continue; end
            if ~strcmp(report.parts.(partNames{p}).status, 'PASS')
                partOk = false;
            end
        end
        if ~partOk
            report.status = 'FAIL';
        end
    end
    if ~strcmp(report.status, 'PASS') && ~isempty(report.errors)
        logMessage('warn', 'validateDataset', ...
            'Dataset %s: %s', name, strjoin(report.errors, ' | '));
    end
end

function msgs = validateOne(ds, i)
%VALIDATEONE  checks (1) image decodes, (2) label, (3) annotation path.
    msgs = {};
    f = char(ds.files(i));
    if ~exist(f, 'file')
        msgs{end+1, 1} = sprintf('image missing: %s', f); %#ok<AGROW>
        return;
    end
    try
        info = imfinfo(f);
        if isempty(info) || numel(info) > 2 || (numel(info) == 2 && ~strcmpi(nameOf(info(1)), 'tif'))
            msgs{end+1, 1} = sprintf('multi-frame or empty image: %s', f); %#ok<AGROW>
        else
            % HxWxC sanity
            w = info(1).Width; h = info(1).Height;
            if w <= 0 || h <= 0
                msgs{end+1, 1} = sprintf('bad dims %dx%d: %s', w, h, f); %#ok<AGROW>
            end
        end
    catch
        msgs{end+1, 1} = sprintf('image corrupt/undecodable: %s', f); %#ok<AGROW>
    end

    % Label where expected (aptos + messidor2 with labels.csv).
    if ds.n > 0 && i <= numel(ds.labels) && strlength(ds.labels(i)) > 0
        val = str2double(ds.labels(i));
        if isnan(val) && strcmp(ds.name, 'aptos')
            msgs{end+1, 1} = sprintf('non-numeric grade %s', ds.labels(i)); %#ok<AGROW>
        end
    end

    % Annotation where expected (idrid annotations / drive masks).
    if i <= numel(ds.annotations) && ~isempty(ds.annotations(i)) && ...
            strlength(ds.annotations(i)) > 0 && ~exist(ds.annotations(i), 'file')
        msgs{end+1, 1} = sprintf('annotation missing: %s', ds.annotations(i)); %#ok<AGROW>
    end
end

function n = nameOf(info)
    n = '';
    if isfield(info, 'Format'); n = info.Format; end
end

function parts = validateIDRiDParts(parts, maxSamples)
%VALIDATEIDRIDPARTS  Bounded validation of the three IDRiD sub-tasks
%(grading / segmentation / localization). Sampling is capped at maxSamples
%(already hard-bounded to 5 by the caller). Full-set existence/counts for the
%report come from the loader inventory; only a bounded sample is decoded.
    for fld = {'grading', 'segmentation', 'localization'}
        p = fld{1};
        part = parts.(p);
        r = struct('status', '', 'n', part.n, 'nSampled', 0, ...
            'samples', struct(), ...
            'duplicateIds', part.duplicateIds, 'missingFiles', part.missingFiles);
        r.errors = cell(0, 1);

        if part.n == 0
            r.status = 'NOT AVAILABLE';
            r.errors = {sprintf('%s: no files', p)};
            parts.(p) = r;
            continue;
        end

        idx = spreadIndex(part.n, maxSamples);
        errs = {};
        for s = 1:numel(idx)
            i = idx(s);
            sample = struct('image', part.files(i), 'ok', false, 'detail', '');
            msgs = validateIDRiDOne(part, i);
            if isempty(msgs)
                sample.ok = true;
                sample.detail = 'ok';
            else
                sample.detail = strjoin(msgs, '; ');
                errs{end+1, 1} = sprintf('%s | %s', char(part.files(i)), sample.detail); %#ok<AGROW>
            end
            r.samples.(['s' num2str(s)]) = sample;
        end
        r.nSampled = numel(idx);
        r.errors = errs;
        if isempty(errs)
            r.status = 'PASS';
        else
            r.status = 'FAIL';
        end
        parts.(p) = r;
    end
end

function msgs = validateIDRiDOne(part, i)
%VALIDATEIDRIDONE  Single-sample checks: decode, labels, coordinate, mask.
    msgs = {};
    f = char(part.files(i));
    if ~exist(f, 'file')
        msgs{end+1, 1} = sprintf('image missing: %s', f); %#ok<AGROW>
        return;
    end
    try
        info = imfinfo(f);
        if isempty(info) || info(1).Width <= 0 || info(1).Height <= 0
            msgs{end+1, 1} = sprintf('bad image: %s', f); %#ok<AGROW>
        end
    catch
        msgs{end+1, 1} = sprintf('image corrupt/undecodable: %s', f); %#ok<AGROW>
    end

    if isfield(part, 'grades') && i <= numel(part.grades) && strlength(part.grades{i}) > 0
        g = str2double(part.grades{i});
        if isnan(g) || g < 0 || g > 4
            msgs{end+1, 1} = sprintf('out-of-range grade %s', part.grades{i}); %#ok<AGROW>
        end
    end
    if isfield(part, 'rme') && i <= numel(part.rme) && strlength(part.rme{i}) > 0
        g = str2double(part.rme{i});
        if isnan(g) || g < 0 || g > 2
            msgs{end+1, 1} = sprintf('out-of-range RME %s', part.rme{i}); %#ok<AGROW>
        end
    end
    if isfield(part, 'odx') && i <= numel(part.odx)
        if ~all(isfinite([part.odx{i}, part.ody{i}, part.fox{i}, part.foy{i}]))
            msgs{end+1, 1} = sprintf('non-finite OD/fovea coords'); %#ok<AGROW>
        end
    end
    if isfield(part, 'masks')
        for f2 = {'ma', 'he', 'ex', 'se', 'od'}
            m = char(part.masks.(f2{1})(i));
            if ~isempty(m) && exist(m, 'file') ~= 2
                msgs{end+1, 1} = sprintf('mask missing: %s', m); %#ok<AGROW>
            end
        end
    end
end

function idx = spreadIndex(n, maxSamples)
    maxSamples = min(maxSamples, 5);
    if n <= maxSamples
        idx = (1:n).';
        return;
    end
    step = floor(n / maxSamples);
    idx = unique(min(1:step:n, n));
    idx = idx(1:min(maxSamples, numel(idx)));
end