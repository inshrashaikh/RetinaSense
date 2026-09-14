function ds = idridLoader(root, p)
%IDRIDLOADER  IDRiD (IEEE DataPort) real-dataset loader.
%
%   ds = idridLoader(root, p)
%
%   Walks the ACTUAL IDRiD distribution under data/raw/IDRiD/ (see
%   data/manifests/README.md "Dataset inventory"):
%
%     A. Segmentation/A. Segmentation/
%       1. Original Images/{a. Training Set,b. Testing Set}/IDRiD_<NN>.jpg
%       2. All Segmentation Groundtruths/.../<lesion>/IDRiD_<NN>_<SUF>.tif
%     B. Disease Grading/B. Disease Grading/
%       1. Original Images/{a. Training Set,b. Testing Set}/IDRiD_<NNN>.jpg
%       2. Groundtruths/*.csv  (Image name, Retinopathy grade, Risk of macular edema)
%     C. Localization/C. Localization/
%       1. Original Images/{a. Training Set,b. Testing Set}/IDRiD_<NNN>.jpg
%       2. Groundtruths/*Markups.csv  (Image No, X, Y — filler rows dropped)
%
%   Grading and localization share the same 516 JPEGs (verified by SHA-256).
%   Segmentation's 81 JPEGs are a separate download (2-digit IDs, NOT
%   assumed to be a renumbered subset of grading's 3-digit IDs).
%
%   Returns a struct whose top-level fields mirror the generic dataset
%   contract (populated from the DISEASE GRADING part) plus a `parts`
%   field holding the three official sub-tasks separately.
%
%   HONESTY: split reflects OFFICIAL train/test; IDRiD must never feed
%   APTOS classifier training (enforced upstream by prepareClassifierData).

    ds = struct('name', string('idrid'), 'source', string('IDRiD (IEEE DataPort)'), ...
        'root', root, 'status', 'CODE ONLY', 'manifestFile', '', 'n', 0, ...
        'files', strings(0,1), 'labels', strings(0,1), ...
        'annotations', strings(0,1), 'split', strings(0,1), ...
        'ids', strings(0,1), 'parts', struct(), 'purpose', '', 'note', '');

    ds.parts.grading       = gradingPart(root);
    ds.parts.segmentation  = segmentationPart(root);
    ds.parts.localization  = localizationPart(root);

    % Integrity checks (cheap, full-set). Duplicates are scored WITHIN each
    % official split: the test-set IDs (001-103) intentionally re-use
    % train-set numbers, so cross-split equality is NOT a duplicate.
    for fld = {'grading', 'localization'}
        part = ds.parts.(fld{1});
        if part.n > 0
            part.duplicateIds = 0;
            for sp = {'train', 'test'}
                spIdx = strcmp(part.split, sp{1});
                [~, ~, ic] = unique(part.ids(spIdx));
                part.duplicateIds = part.duplicateIds + (sum(spIdx) - numel(unique(ic)));
            end
            part.missingFiles = 0;
            for k = 1:part.n
                if exist(part.files{k}, 'file') ~= 2; part.missingFiles = part.missingFiles + 1; end
            end
        else
            part.duplicateIds = 0;
            part.missingFiles = 0;
        end
        ds.parts.(fld{1}) = part;
    end
    sPart = ds.parts.segmentation;
    if sPart.n > 0; sPart.duplicateIds = 0; for sp = {'train','test'}
        spIdx = strcmp(sPart.split, sp{1});
        [~, ~, ic] = unique(sPart.ids(spIdx));
        sPart.duplicateIds = sPart.duplicateIds + (sum(spIdx) - numel(unique(ic)));
    end; else; sPart.duplicateIds = 0; end
    sPart.missingFiles = 0;
    for k = 1:sPart.n
        if exist(sPart.files{k}, 'file') ~= 2; sPart.missingFiles = sPart.missingFiles + 1; end
    end
    ds.parts.segmentation = sPart;

    % Primary view = Disease Grading.
    g = ds.parts.grading;
    ds.n = g.n;
    ds.files = string(g.files);
    ds.ids   = string(g.ids);
    ds.labels = string(g.grades);
    ds.split  = string(g.split);
    ds.annotations = strings(g.n, 1);
    ds.purpose = 'DR grade + lesion + optic-disc + fovea validation (external-only)';
    ds.manifestFile = fullfile(p.data.manifests, 'idrid_manifest.csv');

    if g.n == 0
        ds.status = 'NOT AVAILABLE';
        ds.note = 'IDRiD: no Disease Grading images found.';
        ds.parts.status = ds.status;
        return;
    end

    gDup = ds.parts.grading.duplicateIds; lDup = ds.parts.localization.duplicateIds;
    if gDup > 0 || lDup > 0
        ds.status = 'AVAILABLE + NOT YET VALIDATED (duplicate IDs detected)';
    else
        ds.status = 'AVAILABLE + NOT YET VALIDATED';
    end
    ds.note = sprintf( ...
        'IDRiD: grading %d (train %d test %d), localization %d, segmentation %d. Grades 0-4. Split official; never joins APTOS training.', ...
        g.n, sum(string(g.split) == "train"), sum(string(g.split) == "test"), ...
        ds.parts.localization.n, ds.parts.segmentation.n);
    ds.parts.status = ds.status;
end

% ==================== Grading ====================

function part = gradingPart(root)
    part = struct('n', 0, 'ids', {{}}, 'files', {{}}, 'rel', {{}}, ...
        'grades', {{}}, 'rme', {{}}, 'split', {{}}, ...
        'duplicateIds', 0, 'missingFiles', 0, 'noteIds', {{}}, 'status', '');

    base = fullfile(root, 'B. Disease Grading', 'B. Disease Grading');
    imgBase = fullfile(base, '1. Original Images');
    gtBase  = fullfile(base, '2. Groundtruths');

    csvs    = {fullfile(gtBase, 'a. IDRiD_Disease Grading_Training Labels.csv'), ...
               fullfile(gtBase, 'b. IDRiD_Disease Grading_Testing Labels.csv')};
    imgRoots = {fullfile(imgBase, 'a. Training Set'), fullfile(imgBase, 'b. Testing Set')};
    splitNames = {'train', 'test'};

    for k = 1:2
        if ~exist(imgRoots{k}, 'dir'); continue; end
        d = dir(fullfile(imgRoots{k}, '*.jpg'));
        names = {d.name};
        [grades, rme] = readGradingCsv(csvs{k});
        for i = 1:numel(names)
            id = regexprep(names{i}, '\.jpg$', '');
            idx = find(strcmp(grades.ids, id), 1);
            if isempty(idx)
                part.noteIds{end+1} = sprintf('%s has no grade row in official CSV', id); %#ok
                continue;
            end
            part.ids{end+1}    = id; %#ok
            part.files{end+1}  = fullfile(imgRoots{k}, names{i}); %#ok
            part.rel{end+1}    = relOf(root, part.files{end}); %#ok
            part.grades{end+1} = sprintf('%d', grades.grade(idx)); %#ok
            part.rme{end+1}    = sprintf('%d', rme.grade(idx)); %#ok
            part.split{end+1}  = splitNames{k}; %#ok
        end
    end

    part.n = numel(part.ids);
    if part.n > 0
        [~, order] = sort(part.ids);
        part.ids   = part.ids(order);
        part.files = part.files(order);
        part.rel   = part.rel(order);
        part.grades = part.grades(order);
        part.rme   = part.rme(order);
        part.split = part.split(order);
    end
    part.ids = part.ids(:); part.files = part.files(:); part.rel = part.rel(:);
    part.grades = part.grades(:); part.rme = part.rme(:); part.split = part.split(:);
end

function [grades, rme] = readGradingCsv(csvPath)
    grades = struct('ids', {{}}, 'grade', {{}});
    rme    = struct('ids', {{}}, 'grade', {{}});
    if ~exist(csvPath, 'file'); return; end
    fid = fopen(csvPath, 'rt', 'n', 'UTF-8');
    if fid < 0; return; end
    C = textscan(fid, '%s%f%f%*[^\n]', 'Delimiter', ',', 'HeaderLines', 1);
    fclose(fid);
    ids = strtrim(C{1});
    if ~isempty(ids); ids{1} = regexprep(ids{1}, '^\xEF\xBB\xBF', ''); end
    keep = cellfun(@(x) ~isempty(x) && startsWith(x, 'IDRiD_'), ids) & ...
           ~isnan(C{2}) & ~isnan(C{3});
    grades.ids  = ids(keep);
    grades.grade = C{2}(keep);
    rme.ids     = ids(keep);
    rme.grade   = C{3}(keep);
end

% ==================== Segmentation ====================

function part = segmentationPart(root)
    part = struct('n', 0, 'ids', {{}}, 'files', {{}}, 'rel', {{}}, ...
        'split', {{}}, ...
        'masks', struct('ma', {{}}, 'he', {{}}, 'ex', {{}}, 'se', {{}}, 'od', {{}}), ...
        'duplicateIds', 0, 'missingFiles', 0, 'status', '');

    base    = fullfile(root, 'A. Segmentation', 'A. Segmentation');
    imgBase = fullfile(base, '1. Original Images');
    gtBase  = fullfile(base, '2. All Segmentation Groundtruths');

    lesionDirs  = {'1. Microaneurysms', '2. Haemorrhages', '3. Hard Exudates', ...
                   '4. Soft Exudates', '5. Optic Disc'};
    lesionFields = {'ma', 'he', 'ex', 'se', 'od'};

    imgRoots = {fullfile(imgBase, 'a. Training Set'), fullfile(imgBase, 'b. Testing Set')};
    splitNames = {'train', 'test'};

    for k = 1:2
        if ~exist(imgRoots{k}, 'dir'); continue; end
        d = dir(fullfile(imgRoots{k}, '*.jpg'));
        names = {d.name};
        splitDirName = {'a. Training Set', 'b. Testing Set'};
        for i = 1:numel(names)
            id = regexprep(names{i}, '\.jpg$', '');
            part.ids{end+1} = id; %#ok
            part.files{end+1} = fullfile(imgRoots{k}, names{i}); %#ok
            part.rel{end+1} = relOf(root, part.files{end}); %#ok
            part.split{end+1} = splitNames{k}; %#ok
            for L = 1:numel(lesionFields)
                maskRoot = fullfile(gtBase, splitDirName{k}, lesionDirs{L});
                m = fullfile(maskRoot, [id sprintf('_%s.tif', upper(lesionFields{L}))]);
                if exist(m, 'file') == 2
                    part.masks.(lesionFields{L}){end+1} = relOf(root, m); %#ok
                else
                    part.masks.(lesionFields{L}){end+1} = ''; %#ok
                end
            end
        end
    end
    part.n = numel(part.ids);
    part.ids = part.ids(:); part.files = part.files(:); part.rel = part.rel(:);
    part.split = part.split(:);
    for L = 1:numel(lesionFields)
        part.masks.(lesionFields{L}) = part.masks.(lesionFields{L})(:);
    end
end

% ==================== Localization ====================

function part = localizationPart(root)
    part = struct('n', 0, 'ids', {{}}, 'files', {{}}, 'rel', {{}}, ...
        'split', {{}}, 'odx', {{}}, 'ody', {{}}, 'fox', {{}}, 'foy', {{}}, ...
        'duplicateIds', 0, 'missingFiles', 0, 'status', '');

    base    = fullfile(root, 'C. Localization', 'C. Localization');
    imgBase = fullfile(base, '1. Original Images');
    gtBase  = fullfile(base, '2. Groundtruths');

    odCsvs = {fullfile(gtBase, '1. Optic Disc Center Location', 'a. IDRiD_OD_Center_Training Set_Markups.csv'), ...
              fullfile(gtBase, '1. Optic Disc Center Location', 'b. IDRiD_OD_Center_Testing Set_Markups.csv')};
    foCsvs = {fullfile(gtBase, '2. Fovea Center Location', 'IDRiD_Fovea_Center_Training Set_Markups.csv'), ...
              fullfile(gtBase, '2. Fovea Center Location', 'IDRiD_Fovea_Center_Testing Set_Markups.csv')};
    imgRoots = {fullfile(imgBase, 'a. Training Set'), fullfile(imgBase, 'b. Testing Set')};
    splitNames = {'train', 'test'};

    for k = 1:2
        if ~exist(imgRoots{k}, 'dir'); continue; end
        d = dir(fullfile(imgRoots{k}, '*.jpg'));
        names = {d.name};
        od = readMarkupCsv(odCsvs{k});
        fo = readMarkupCsv(foCsvs{k});
        for i = 1:numel(names)
            id = regexprep(names{i}, '\.jpg$', '');
            oi = find(strcmp(od.ids, id), 1);
            fi = find(strcmp(fo.ids, id), 1);
            if isempty(oi) || isempty(fi); continue; end
            part.ids{end+1} = id; %#ok
            part.files{end+1} = fullfile(imgRoots{k}, names{i}); %#ok
            part.rel{end+1} = relOf(root, part.files{end}); %#ok
            part.split{end+1} = splitNames{k}; %#ok
            part.odx{end+1} = od.x{oi}; %#ok
            part.ody{end+1} = od.y{oi}; %#ok
            part.fox{end+1} = fo.x{fi}; %#ok
            part.foy{end+1} = fo.y{fi}; %#ok
        end
    end
    part.n = numel(part.ids);
    if part.n > 0
        [~, order] = sort(part.ids);
        part.ids   = part.ids(order); part.files = part.files(order);
        part.rel   = part.rel(order); part.split = part.split(order);
        part.odx   = part.odx(order); part.ody = part.ody(order);
        part.fox   = part.fox(order); part.foy = part.foy(order);
    end
    part.ids = part.ids(:); part.files = part.files(:); part.rel = part.rel(:);
    part.split = part.split(:); part.odx = part.odx(:); part.ody = part.ody(:);
    part.fox = part.fox(:); part.foy = part.foy(:);
end

function md = readMarkupCsv(csvPath)
    md = struct('ids', {{}}, 'x', {{}}, 'y', {{}});
    if ~exist(csvPath, 'file'); return; end
    fid = fopen(csvPath, 'rt', 'n', 'UTF-8');
    if fid < 0; return; end
    C = textscan(fid, '%s%f%f%*[^\n]', 'Delimiter', ',', 'HeaderLines', 1);
    fclose(fid);
    ids = strtrim(C{1});
    if ~isempty(ids); ids{1} = regexprep(ids{1}, '^\xEF\xBB\xBF', ''); end
    if isempty(ids); return; end
    keep = ~cellfun(@isempty, ids) & cellfun(@(x) startsWith(x, 'IDRiD_'), ids) & ...
           ~isnan(C{2}) & ~isnan(C{3});
    md.ids = ids(keep);
    md.x   = num2cell(C{2}(keep));
    md.y   = num2cell(C{3}(keep));
end

% ==================== helpers ====================

function rel = relOf(root, absPath)
    rel = strrep(strrep(char(absPath), root, ''), '\', '/');
    rel = strrep(rel, '\', '/');
    if startsWith(rel, '/'); rel = rel(2:end); end
end