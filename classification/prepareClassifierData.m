function data = prepareClassifierData(manifestFile, inputSize)
%PREPARECLASSIFIERDATA  Build train/val/test datastores for DR classifier.
%
%   data = prepareClassifierData(manifestFile, inputSize)
%   data = prepareClassifierData()            % uses manifest from config/paths.m
%
%   manifestFile: path to a CSV with columns (docs/ARCHITECTURE.md §8):
%                image, eye_id, grade, split, source
%                image = absolute or repo-relative path to the fundus image.
%                split = train | val | test | external.
%   inputSize:   [H W C] classifier input size (default from classification_config).
%
%   Returns a struct ready for trainClassifier / classifyImage:
%     data.train   imageDatastore (with Labels = grade 0..4)
%     data.val     imageDatastore
%     data.test    imageDatastore
%     data.external imageDatastore   % Messidor-2 EXTERNAL ONLY (never train/val)
%     data.classWeights 1x5 inverse-frequency weights (imbalance handling)
%     data.note    string describing what was prepared / any caveats
%
%   Guardrails (AGENTS.md / docs/ARCHITECTURE.md §8):
%     - messidor2 rows are only ever split=external; they are never admitted to
%       train/val, satisfying "Messidor-2 is external-validation only."
%     - A genuinely empty manifest (schema-only folds.csv) raises a clear error
%       rather than pretending data exists. Real execution requires real data.
%
%   Augmentation (flip/rotate/scale/color-jitter) is applied at training time in
%   trainClassifier.m with a fixed seed (config.classification.train.augmentation).

    cfg = experiment_config();
    if nargin < 1; manifestFile = ''; end
    if nargin < 2 || isempty(inputSize)
        inputSize = cfg.classification.classify.inputSize;
    end
    if isempty(manifestFile)
        manifestFile = fullfile(paths().data.manifests, 'folds.csv');
    end

    if ~exist(manifestFile, 'file')
        raiseError('prepareClassifierData', 'ManifestMissing', ...
            'Manifest not found: %s', manifestFile);
    end

    T = readtable(manifestFile, 'TextType', 'string');
    if isempty(T) || ~all(ismember({'image','eye_id','grade','split','source'}, T.Properties.VariableNames))
        raiseError('prepareClassifierData', 'ManifestEmpty', ...
            'Manifest has no usable rows or misses required columns: %s', manifestFile);
    end
    if height(T) == 0
        raiseError('prepareClassifierData', 'ManifestEmpty', ...
            'Manifest %s is schema-only (no data rows). Add APTOS/IDRiD/Messidor-2 rows first.', manifestFile);
    end

    % Enforce the Messidor-2 external-only rule up front.
    extSrcId = strcmpi(T.source, 'messidor2');
    if any(extSrcId & ~strcmpi(T.split, 'external'))
        bad = find(extSrcId & ~strcmpi(T.split, 'external'), 1);
        raiseError('prepareClassifierData', 'MessidorLeak', ...
            'Messidor-2 row %d assigned to non-external split (train/val leak).', bad);
    end

    root = paths().root;
    data = struct();

    % Per-split imageDatastore with Labels = grade (0..4).
    for splitName = {'train','val','test','external'}
        s = splitName{1};
        rows = T(strcmpi(T.split, s), :);
        if height(rows) == 0
            data.(s) = [];
            data.(['n_' s]) = 0;
            continue;
        end
        ds = buildDatastore(rows, root, cfg);
        data.(s)      = ds;
        data.(['n_' s]) = numel(ds.Files);
    end

    % Inverse-frequency class weights over the TRAINING labels (imbalance).
    yTr = data.train.Labels;
    w = zeros(1, cfg.classification.numClasses);
    for g = 0:(cfg.classification.numClasses-1)
        c = sum(yTr == g);
        w(g+1) = 1 / max(1, c);
    end
    w = w / sum(w) * cfg.classification.numClasses;   % normalize so mean weight = 1
    data.classWeights = w;

    data.inputSize   = inputSize;
    data.manifestFile = manifestFile;
    data.note = sprintf( ...
        'Prepared splits from %s: train=%d val=%d test=%d external=%d. Messidor-2 external-only enforced.', ...
        manifestFile, data.n_train, data.n_val, data.n_test, data.n_external);
end

function ds = buildDatastore(rows, root, cfg)
%BUILDDATASTORE  Resolve image paths relative to repo root and create a
% labeled imageDatastore with grade labels 0..4.
    files = cell(height(rows), 1);
    for i = 1:height(rows)
        p = rows.image(i);
        if ~isempty(p) && ~isfile(p) && ~isfile(fullfile(root, p))
            raiseError('prepareClassifierData', 'ImageMissing', ...
                'Image row %d not found (tried ''%s'' and ''%s'').', i, p, fullfile(root, p));
        end
        if isfile(p); files{i} = char(p); else; files{i} = fullfile(root, char(p)); end
    end
    labels = rows.grade;
    ds = imageDatastore(files, 'Labels', categorical(labels, 0:(cfg.classification.numClasses-1)));
end
