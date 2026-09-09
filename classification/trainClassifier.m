function net = trainClassifier(backbone, varargin)
%TRAINCLASSIFIER  Fine-tune the DR grading CNN via transfer learning.
%
%   net = trainClassifier(backbone)
%   net = trainClassifier()                 % uses cfg chosen backbone
%   net = trainClassifier(backbone, 'manifest', folds.csv, 'maxEpochs', 10)
%
%   backbone: 'resnet50' | 'efficientnetb0' (cfg.classification.train.
%             backboneCandidates). Fine-tunes the ImageNet-pretrained network
%             on APTOS 2019 (docs/ARCHITECTURE.md §3.2, §2 Stage 6).
%
%   The network head (final fully-connected + softmax + classification layers)
%   is swapped for a 5-class ICDR 0-4 head and fine-tuned on
%   data/train (prepared by prepareClassifierData), validated on data/val,
%   then saved to data/models/{backbone}_dr_aptos.mat (§8).
%
%   HONESTY (AGENTS.md): returns a trained model only after real training on
%   real data. With no rows in the manifest it raises a clear error; it never
%   fabricates a network or accuracy numbers.
%
%   All hyper-parameters come from config/classification_config.m (train.*),
%   including the per-backbone head-layer names — no magic numbers in code.

    cfg = experiment_config();
    tc  = cfg.classification.train;
    if nargin < 1 || isempty(backbone)
        if isempty(cfg.model.backbone)
            raiseError('trainClassifier', 'NoBackbone', ...
                'No backbone selected. Run scripts/benchmark_backbones.m first or pass a backbone.');
        end
        backbone = cfg.model.backbone;
    end
    backbone = validatestring(backbone, tc.backboneCandidates, 'trainClassifier', 'backbone');

    p = inputParser;
    addParameter(p, 'manifest', fullfile(paths().data.manifests, 'folds.csv'));
    addParameter(p, 'maxEpochs', tc.maxEpochs);
    addParameter(p, 'miniBatchSize', tc.miniBatchSize);
    parse(p, varargin{:});
    opts = p.Results;

    data = prepareClassifierData(opts.manifest);      % train/val/test + weights
    if isempty(data.train) || data.n_train < 10
        raiseError('trainClassifier', 'InsufficientData', ...
            'Need >= 10 training images; manifest has %d. Add real APTOS data.', data.n_train);
    end

    % ---- Pretrained backbone + 5-class head (config-driven layer names) ----
    switch backbone
        case 'resnet50'
            base = resnet50();
        case 'efficientnetb0'
            base = efficientnetb0();
    end
    lgraph = swapHead(base, tc.headLayers.(backbone), cfg.classification.numClasses);

    % ---- Fixed-seed augmentation (reproducibility, cfg.seed) ----
    rng(cfg.seed, 'twister');
    aug = imageDataAugmenter( ...
        'RandXReflection', tc.augmentation, ...
        'RandRotation',    [0 tc.augmentation*10], ...
        'RandXScale',      [1-0.1*tc.augmentation 1+0.1*tc.augmentation], ...
        'RandYScale',      [1-0.1*tc.augmentation 1+0.1*tc.augmentation]);

    augTr = augmentedImageDatastore(data.inputSize(1:2), data.train, ...
        'DataAugmentation', aug, 'OutputSizeMode', 'resize');
    augVa = augmentedImageDatastore(data.inputSize(1:2), data.val, ...
        'OutputSizeMode', 'resize');

    options = trainingOptions('sgdm', ...
        'MiniBatchSize',       opts.miniBatchSize, ...
        'MaxEpochs',           opts.maxEpochs, ...
        'InitialLearnRate',    tc.initialLearnRate, ...
        'Shuffle',             'every-epoch', ...
        'ValidationData',      augVa, ...
        'ValidationFrequency', max(1, round(data.n_train/opts.miniBatchSize)), ...
        'Verbose',             true, ...
        'Plots',               'none');

    net = trainNetwork(augTr, lgraph, options);

    % ---- Persist model + metadata (docs/ARCHITECTURE.md §8) ----
    modelFile = fullfile(paths().data.models, sprintf('%s_dr_aptos.mat', backbone));
    save(modelFile, 'net', 'backbone');
    logMessage('info', 'trainClassifier', ...
        sprintf('Saved %s model -> %s (train=%d)', backbone, modelFile, data.n_train));
end

function lgraph = swapHead(base, layerNames, numClasses)
%SWAPHEAD  Standard transfer-learning: replace the final learnable FC + the
% softmax + classification layers with a {numClasses}-class head.
    lgraph = layerGraph(base);

    newLearnable = fullyConnectedLayer(numClasses, 'Name', 'dr_fc', ...
        'WeightLearnRateFactor', 10, 'BiasLearnRateFactor', 10);
    lgraph = replaceLayer(lgraph, layerNames.learnable, newLearnable);

    newClass = classificationLayer('Name', 'dr_out');
    lgraph = replaceLayer(lgraph, layerNames.classoutput, newClass);
end
