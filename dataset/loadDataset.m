function ds = loadDataset(name)
%LOADDATASET  Dataset loader entry point (real files only).
%
%   ds = loadDataset(name)   name = 'aptos' | 'idrid' | 'drive' | 'messidor2'
%   ds = loadDataset()       loads every known dataset into a registry cell
%
%   Returns a struct describing a dataset grounded in REAL on-disk files:
%     ds.name         dataset key
%     ds.source       official source name
%     ds.root         data/raw/<dataset> root (config/paths.m)
%     ds.status       'NOT AVAILABLE' | 'AVAILABLE + NOT YET VALIDATED'
%     ds.manifestFile committed manifest path (real rows only)
%     ds.files        Nx1 string[] of resolved absolute image paths
%     ds.labels       Nx1 label column (grade) where legitimately available
%     ds.annotations  Nx1 string[] of resolved annotation/mask paths
%     ds.split        Nx1 split column ('train'|'val'|'test'|'external')
%     ds.note         human-readable caveat
%
%   HONESTY: loaders never invent images, labels or masks. If data/raw/<name>
%   is absent or empty, status = 'NOT AVAILABLE' and files/labels are empty.
%   This module is the single place the rest of the pipeline learns about a
%   dataset; evaluation hooks and tests consume its output.

    if nargin < 1 || isempty(name)
        names = {'aptos', 'idrid', 'drive', 'messidor2'};
        ds = cell(numel(names), 1);
        for i = 1:numel(names)
            ds{i} = loadDataset(names{i});
        end
        return;
    end

    known = {'aptos', 'idrid', 'drive', 'messidor2'};
    if ~any(strcmp(name, known))
        raiseError('loadDataset', 'UnknownDataset', ...
            'Unknown dataset ''%s''. Known: aptos | idrid | drive | messidor2.', name);
    end

    p = paths();
    root = p.data.datasets.(name);

    switch name
        case 'aptos'
            ds = aptosLoader(root, p);
        case 'idrid'
            ds = idridLoader(root, p);
        case 'drive'
            ds = driveLoader(root, p);
        case 'messidor2'
            ds = messidor2Loader(root, p);
        otherwise
            raiseError('loadDataset', 'UnknownDataset', ...
                sprintf('Unknown dataset ''%s''.', name));
    end
end

function ds = aptosLoader(root, p)
    ds = blank('aptos', 'APTOS 2019', root);
    imagesRoot = p.data.images;               % <grade>/img_*.png
    if ~exist(imagesRoot, 'dir')
        ds.status = 'NOT AVAILABLE';
        ds.note   = sprintf('APTOS images root missing: %s', imagesRoot);
        return;
    end
    pngs = dir(fullfile(imagesRoot, '*', '*.png'));
    ds.n = numel(pngs);
    ds.files = strings(ds.n, 1);
    ds.labels = strings(ds.n, 1);
    ds.split = repmat("train", ds.n, 1);      % canonical split = folds.csv
    for i = 1:ds.n
        [~, g] = fileparts(pngs(i).folder);
        ds.files(i)  = fullfile(pngs(i).folder, pngs(i).name);
        ds.labels(i) = string(g);
    end
    folds = fullfile(p.data.manifests, 'folds.csv');
    if exist(folds, 'file')
        ds.note = sprintf('APTOS %d images; canonical split in folds.csv (train/val/test).', ds.n);
        ds.status = 'AVAILABLE + NOT YET VALIDATED';
    else
        ds.note = 'APTOS images present but folds.csv missing.';
        ds.status = 'AVAILABLE + NOT YET VALIDATED';
    end
    ds.manifestFile = fullfile(p.data.manifests, 'aptos_manifest.csv');
end

function ds = driveLoader(root, p)
    ds = blank('drive', 'DRIVE (grand-challenge.org)', root);
    [trainImgs, trainMasks, trainWm] = driveSplit(root, 'training');
    [testImgs,  testMasks,  testWm]  = driveSplit(root, 'test');
    imgs  = [trainImgs; testImgs];
    masks = [trainMasks; testMasks];
    if isempty(imgs)
        ds.status = 'NOT AVAILABLE';
        ds.note   = 'DRIVE: no training/test images found.';
        return;
    end
    ds.n = numel(imgs);
    ds.files = strings(ds.n, 1);
    ds.annotations = strings(ds.n, 1);
    ds.split = strings(ds.n, 1);
    for i = 1:ds.n
        ds.files(i) = imgs{i};
        ds.annotations(i) = masks{i};
        if i <= numel(trainImgs); ds.split(i) = "train"; else; ds.split(i) = "test"; end
    end
    ds.purpose = 'vessel segmentation validation';
    ds.note = sprintf('DRIVE: %d train + %d test image/mask pairs.', ...
        numel(trainImgs), numel(testImgs));
    ds.status = 'AVAILABLE + NOT YET VALIDATED';
    ds.manifestFile = fullfile(p.data.manifests, 'drive_manifest.csv');
end

function ds = messidor2Loader(root, p)
    ds = blank('messidor2', 'Messidor-2 (official adcis)', root);
    imgDir = fullfile(root, 'images');
    imgs = collectImages(imgDir);
    labelFile = fullfile(root, 'labels.csv');
    hasLabels = exist(labelFile, 'file') == 2;

    if isempty(imgs)
        ds.status = 'NOT AVAILABLE';
        ds.note   = sprintf('Messidor-2: no images under %s', imgDir);
        return;
    end
    ds.n = numel(imgs);
    ds.files = strings(ds.n, 1);
    ds.split = repmat("external", ds.n, 1);     % EXTERNAL ONLY
    ds.labels = strings(ds.n, 1);
    for i = 1:ds.n
        ds.files(i) = imgs{i};
    end
    if hasLabels
        T = readtable(labelFile, 'TextType', 'string');
        if ismember('image', T.Properties.VariableNames) && ismember('grade', T.Properties.VariableNames)
            for i = 1:ds.n
                [~, f, ~] = fileparts(ds.files(i));
                m = find(cellfun(@(x) contains(string(x), f), cellstr(T.image)), 1); %#ok<FNDSB>
                if ~isempty(m); ds.labels(i) = string(T.grade(m)); end
            end
        end
    end
    ds.purpose = 'external DR validation';
    if hasLabels
        ds.status = 'AVAILABLE + NOT YET VALIDATED';
        ds.note   = 'Messidor-2: real images + legitimate grade labels present.';
    else
        ds.status = 'AVAILABLE + NOT YET VALIDATED (labels absent)';
        ds.note   = 'Messidor-2 images present but NO legitimate labels.csv — gradients never inferred from filenames. External validation metrics unavailable until an official label source is provided.';
    end
    ds.manifestFile = fullfile(p.data.manifests, 'messidor2_manifest.csv');
end

function ds = blank(name, source, root)
    ds = struct('name', string(name), 'source', string(source), ...
        'root', root, 'status', 'CODE ONLY', ...
        'manifestFile', '', 'n', 0, ...
        'files', strings(0, 1), 'labels', strings(0, 1), ...
        'annotations', strings(0, 1), 'split', strings(0, 1), ...
        'purpose', '', 'note', '');
end

function imgs = collectImages(imgDir)
    imgs = {};
    if ~exist(imgDir, 'dir'); return; end
    for ext = {'*.png', '*.jpg', '*.jpeg', '*.tif', '*.bmp'}
        d = dir(fullfile(imgDir, ext{1}));
        for k = 1:numel(d)
            imgs{end+1, 1} = fullfile(imgDir, d(k).name); %#ok<AGROW>
        end
    end
    imgs = sort(imgs);
end

function [imgs, masks, withMask] = driveSplit(root, split)
    imgs = {}; masks = {}; withMask = 0;
    imgDir = fullfile(root, split, 'images');
    maskDir = fullfile(root, split, '1st_manual');
    if ~exist(imgDir, 'dir'); return; end
    for ext = {'*.tif', '*.png'}
        d = dir(fullfile(imgDir, ext{1}));
        for k = 1:numel(d)
            imgs{end+1, 1} = fullfile(imgDir, d(k).name); %#ok<AGROW>
            m = '';
            if exist(maskDir, 'dir')
                [~, f, ~] = fileparts(d(k).name);
                if exist(fullfile(maskDir, [f '.gif']), 'file')
                    m = fullfile(maskDir, [f '.gif']);
                elseif exist(fullfile(maskDir, [f '.png']), 'file')
                    m = fullfile(maskDir, [f '.png']);
                end
            end
            masks{end+1, 1} = m; %#ok<AGROW>
        end
    end
    imgs = sort(imgs); masks = sort(masks);
    withMask = sum(strlength(string(masks)) > 0);
end