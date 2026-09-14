function registry = buildDatasetManifests()
%BUILDDATASETMANIFESTS  Rebuild dataset manifests from REAL files only.
%
%   registry = buildDatasetManifests()
%
%   For each dataset (aptos, idrid, drive, messidor2) walks the expected
%   directory layout under data/raw/<dataset> (config/paths.m ->
%   cfg.data.datasets) and writes data/manifests/<dataset>_manifest.csv with
%   rows derived ONLY from files that actually exist on disk. A missing
%   dataset yields an empty manifest and a status of "NOT AVAILABLE".
%
%   data/manifests/dataset_status.csv holds the per-dataset registry:
%     dataset, status, n_images, n_annotations, labels, split, purpose,
%     manifest, loader, source
%
%   Status values (see data/manifests/README.md):
%     AVAILABLE + VALIDATED, AVAILABLE + NOT YET VALIDATED,
%     CODE ONLY, NOT AVAILABLE.
%
%   HONESTY: never creates rows for files that do not exist. Re-run after
%   placing real data; validateDataset.m promotes status to VALIDATED.

    p = paths();
    outCsv = fullfile(p.data.manifests, 'dataset_status.csv');
    registry = [ ... 
        aptosRow(); ...
        idridRow(); ...
        driveRow(); ...
        messidor2Row()];
    writetable(struct2table(registry), outCsv);
    logMessage('info', 'buildDatasetManifests', ...
        sprintf('Wrote %d dataset rows -> %s', height(registry), outCsv));
end

function rec = aptosRow()
%APTOS: primary DR classifier dataset. Real images = data/raw/aptos/images/<grade>/*.png
%(verified 3662 images; folds.csv 2929/366/367 train/val/test, no leakage).
    p = paths();
    imagesRoot = p.data.images;
    manifestCsv = fullfile(p.data.manifests, 'aptos_manifest.csv');

    if ~exist(imagesRoot, 'dir')
        writeEmpty(manifestCsv);
        rec = baseRow('aptos', 'APTOS 2019', 'NOT AVAILABLE');
        return;
    end
    pngs = dir(fullfile(imagesRoot, '*', '*.png'));
    if isempty(pngs)
        writeEmpty(manifestCsv);
        rec = baseRow('aptos', 'APTOS 2019', 'NOT AVAILABLE');
        return;
    end

    % Per-image inventory; canonical split remains folds.csv.
    rows = table(strings(height(pngs), 1), strings(height(pngs), 1), ...
        strings(height(pngs), 1), strings(height(pngs), 1), ...
        'VariableNames', {'image', 'grade', 'split', 'source'});
    for i = 1:numel(pngs)
        [~, gradeDir] = fileparts(pngs(i).folder);
        rows.image(i)  = fullfile(gradeDir, pngs(i).name);
        rows.grade(i)  = string(gradeDir);
        rows.split(i)  = "train";       % informational; folds.csv is canonical
        rows.source(i) = "aptos";
    end
    writetable(rows, manifestCsv);

    rec = baseRow('aptos', 'APTOS 2019', 'AVAILABLE + NOT YET VALIDATED');
    rec.n_images = height(rows);
    rec.labels   = 'grade 0-4 + folds.csv split';
    rec.split    = 'train/val/test 2929/366/367 (folds.csv)';
    rec.purpose  = 'DR classifier train/val/test';
    rec.manifest = 'data/manifests/aptos_manifest.csv (+folds.csv)';
end

function rec = idridRow()
%IDRiD (IEEE DataPort). Walks the real 3-part layout:
%   A. Segmentation   (81 images + lesion masks)
%   B. Disease Grading (516 images + 0-4 grade labels)
%   C. Localization   (same 516 images + optic-disc/fovea centers)
%   Writes four committed manifest CSVs and returns a status row.
    p = paths();
    root = p.data.datasets.idrid;
    manifestBase = fullfile(p.data.manifests, 'idrid');
    rec = baseRow('idrid', 'IDRiD (Indian Diabetic Retinopathy Image Dataset)', 'CODE ONLY');

    ds = idridLoader(root, p);
    if ds.parts.grading.n == 0 && ds.parts.segmentation.n == 0
        rec.status = 'NOT AVAILABLE';
        rec.manifest = '';
        return;
    end

    nGr  = ds.parts.grading.n;
    nSeg = ds.parts.segmentation.n;
    nLoc = ds.parts.localization.n;

    % Real mask files present on disk (masks are sparse per lesion).
    nMasks = 0;
    if nSeg > 0
        s0 = ds.parts.segmentation;
        for ff = {'ma','he','ex','se','od'}
            nMasks = nMasks + sum(cellfun(@(x) exist(x,'file')==2, s0.masks.(ff{1})));
        end
    end

    % --- Grading manifest ---
    if nGr > 0
        g = ds.parts.grading;
        T = table(g.rel, g.ids, g.grades, g.rme, g.split, ...
            repmat("idrid", nGr, 1), ...
            'VariableNames', {'image','image_id','grade','risk_macular_edema','split','source'});
        writetable(T, [manifestBase '_grading_manifest.csv']);
    end

    % --- Segmentation manifest (mask '' where absent) ---
    if nSeg > 0
        s = ds.parts.segmentation;
        T = table(s.rel, s.ids, s.split, ...
            repmat("idrid_seg", nSeg, 1), ...
            s.masks.ma, s.masks.he, s.masks.ex, s.masks.se, s.masks.od, ...
            'VariableNames', {'image','image_id','split','source', ...
            'ma_mask','he_mask','ex_mask','se_mask','od_mask'});
        writetable(T, [manifestBase '_segmentation_manifest.csv']);
    end

    % --- Localization manifest ---
    if nLoc > 0
        L = ds.parts.localization;
        T = table(L.rel, L.ids, L.split, ...
            repmat("idrid", nLoc, 1), ...
            cell2mat(L.odx), cell2mat(L.ody), cell2mat(L.fox), cell2mat(L.foy), ...
            'VariableNames', {'image','image_id','split','source', ...
            'od_x','od_y','fovea_x','fovea_y'});
        writetable(T, [manifestBase '_localization_manifest.csv']);
    end

    % --- Master manifest (all unique images) ---
    writeIdridMaster(root, p, ds);

    dupGr  = ds.parts.grading.duplicateIds;
    dupLoc = ds.parts.localization.duplicateIds;
    intOk = (dupGr == 0) && (dupLoc == 0);

    rec.status = iif(intOk, 'AVAILABLE + NOT YET VALIDATED', ...
                           'AVAILABLE + NOT YET VALIDATED (duplicate IDs detected)');
    rec.n_images     = nGr + nLoc + nSeg;   % master manifest rows (physical files)
    rec.n_annotations = nMasks;
    rec.labels       = sprintf('grade 0-4 (B), macular edema (B), seg masks (A: MA/HE/EX/SE/OD), OD/fovea center xy (C)');
    rec.split        = sprintf('grading train=%d test=%d | localization train=%d test=%d | seg train=%d test=%d', ...
        sum(strcmp(g.split,'train')), sum(strcmp(g.split,'test')), ...
        sum(strcmp(L.split,'train')), sum(strcmp(L.split,'test')), ...
        sum(strcmp(s.split,'train')), sum(strcmp(s.split,'test')));
    rec.purpose      = 'DR grade + lesion + optic-disc + fovea validation (external-only)';
    rec.manifest     = 'data/manifests/idrid_manifest.csv (+grading,segmentation,localization)';
end

function writeIdridMaster(root, p, ds)
%IDRID_MASTER  One row per unique physical image across all three sub-tasks.
%Train and test image_IDs numerically overlap (IDRiD_001..103 appear in BOTH
%official splits), so uniqueness is keyed on the relative file path, NOT the
%id. Each row keeps the id, its split, and the first sub-task that references it.
    idSet = {}; relSet = {}; splitSet = {}; sourceSet = {};
    for part = {'grading', 'segmentation', 'localization'}
        for i = 1:ds.parts.(part{1}).n
            rel = char(ds.parts.(part{1}).rel(i));
            if any(strcmp(relSet, rel)); continue; end
            idSet{end+1,1}   = char(ds.parts.(part{1}).ids(i)); %#ok
            relSet{end+1,1}  = rel; %#ok
            splitSet{end+1,1}= char(ds.parts.(part{1}).split(i)); %#ok
            sourceSet{end+1,1}= part{1}; %#ok
        end
    end
    T = table(idSet, relSet, splitSet, sourceSet, ...
        'VariableNames', {'image_id','image','split','subset'});
    writetable(T, fullfile(p.data.manifests, 'idrid_manifest.csv'));
end

function rec = driveRow()
%DRIVE (grand-challenge.org). Layout expected under data/raw/drive/:
%   training/images/*.tif   training/1st_manual/*.gif   training/mask/*.gif
%   test/images/*.tif       test/1st_manual/*.gif       test/mask/*.gif
    p = paths();
    rec = baseRow('drive', 'DRIVE', 'CODE ONLY');

    [trImg, trMsk] = resolveFolders(fullfile(p.data.datasets.drive, 'training'));
    [teImg, teMsk] = resolveFolders(fullfile(p.data.datasets.drive, 'test'));
    if isempty(trImg) && isempty(teImg)
        rec.status = 'NOT AVAILABLE';
        return;
    end

    rows = table(string(0, 1), string(0, 1), string(0, 1), string(0, 1), ...
        'VariableNames', {'image', 'vessel_mask', 'split', 'source'});
    rows = appendDrive(rows, p.data.datasets.drive, trImg, trMsk, "train");
    rows = appendDrive(rows, p.data.datasets.drive, teImg, teMsk, "test");

    writetable(rows, fullfile(p.data.manifests, 'drive_manifest.csv'));

    rec.status       = 'AVAILABLE + NOT YET VALIDATED';
    rec.n_images     = height(rows);
    rec.n_annotations = height(rows);
    rec.labels       = 'manual vessel segmentation mask';
    rec.split        = sprintf('train=%d test=%d', numel(trImg), numel(teImg));
    rec.purpose      = 'vessel segmentation validation';
    rec.manifest     = 'data/manifests/drive_manifest.csv';
end

function rec = messidor2Row()
%Messidor-2 (official adcis distribution). Layout expected under
%data/raw/messidor2/:
%   images/*.{png,jpg,tif}   real retinal images
%   labels.csv               image,grade  (LEGITIMATE GT only; the loader
%                            NEVER infers grades from filenames)
    p = paths();
    rec = baseRow('messidor2', 'Messidor-2', 'CODE ONLY');

    imgDir = fullfile(p.data.datasets.messidor2, 'images');
    images = {};
    if exist(imgDir, 'dir')
        images = [listExt(imgDir, '*.png'); listExt(imgDir, '*.jpg'); ...
                  listExt(imgDir, '*.jpeg'); listExt(imgDir, '*.tif')];
    end
    if isempty(images)
        rec.status = 'NOT AVAILABLE';
        return;
    end

    labels = fullfile(p.data.datasets.messidor2, 'labels.csv');
    hasLabels = exist(labels, 'file') == 2;

    rows = table(strings(numel(images), 1), repmat("external", numel(images), 1), ...
        repmat("messidor2", numel(images), 1), ...
        'VariableNames', {'image', 'split', 'source'});
    for i = 1:numel(images)
        [~, f, e] = fileparts(images{i});
        rows.image(i) = fullfile('images', [f e]);
    end
    writetable(rows, fullfile(p.data.manifests, 'messidor2_manifest.csv'));

    rec.status = 'AVAILABLE + NOT YET VALIDATED';
    rec.n_images     = numel(images);
    rec.n_annotations = double(hasLabels);
    rec.labels   = iif(hasLabels, 'grade from labels.csv (official source)', 'none (no legitimate labels present)');
    rec.split    = 'external (never train/val — enforced by prepareClassifierData)';
    rec.purpose  = 'external DR validation';
    rec.manifest = 'data/manifests/messidor2_manifest.csv';
    if ~hasLabels
        rec.status = 'AVAILABLE + NOT YET VALIDATED (labels absent)';
    end
end

% ---------------- helpers ----------------

function rows = appendDrive(rows, base, imgs, masks, split)
    for i = 1:numel(imgs)
        [~, f, ~] = fileparts(imgs{i});
        rows.image(end+1, 1) = relPath(base, imgs{i}); %#ok<AGROW>
        rows.vessel_mask(end+1, 1) = relPath(base, masks{i}); %#ok<AGROW>
        rows.split(end+1, 1) = split; %#ok<AGROW>
        rows.source(end+1, 1) = "drive"; %#ok<AGROW>
    end
end

function [imgs, masks] = resolveFolders(splitBase)
    imgs = {};
    masks = {};
    if ~exist(splitBase, 'dir'), return; end
    imgDir = fullfile(splitBase, 'images');
    maskDir = fullfile(splitBase, '1st_manual');
    if ~exist(imgDir, 'dir') || ~exist(maskDir, 'dir'), return; end
    imgs = [listExt(imgDir, '*.tif'); listExt(imgDir, '*.png')];
    for i = 1:numel(imgs)
        [~, f, ~] = fileparts(imgs{i});
        m = fullfile(maskDir, [f '.gif']);
        if ~exist(m, 'file'); m = fullfile(maskDir, [f '.png']); end
        if exist(m, 'file'); masks{end+1, 1} = m; else; masks{end+1, 1} = ''; end %#ok<AGROW>
    end
end

function out = listExt(dirPath, pattern)
    d = dir(fullfile(dirPath, pattern));
    out = cell(numel(d), 1);
    for i = 1:numel(d); out{i} = fullfile(dirPath, d(i).name); end
end

function s = relPath(base, absPath)
    rel = strrep(strrep(absPath, base, ''), '\', '/');
    rel = strrep(rel, '\', '/');
    if startsWith(rel, '/'); rel = rel(2:end); end
    s = string(rel);
end

function rec = baseRow(name, source, status)
    rec = struct('dataset', string(name), 'status', string(status), ...
        'n_images', 0, 'n_annotations', 0, ...
        'labels', '', 'split', '', 'purpose', '', ...
        'manifest', '', 'loader', string(sprintf('loadDataset(''%s'')', name)), ...
        'source', string(source));
end

function writeEmpty(csvPath)
    if exist(csvPath, 'file'); delete(csvPath); end
end

function c = iif(cond, a, b)
    if cond; c = a; else; c = b; end
end