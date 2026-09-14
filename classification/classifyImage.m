function grading = classifyImage(image, net, params)
%CLASSIFYIMAGE  Stage 6: DR severity grading, 5-class + referable-DR.
%
%   grading = classifyImage(image, net, params)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.4):
%     grading.rawProbs     1x5 double, P(grade 0..4), sums to 1
%     grading.grade        0..4 (argmax)
%     grading.referableProb P(grade >= 2)
%     grading.referable    referableProb >= referThreshold (config)
%     grading.modelFile    name of the trained net used ('' if mock)
%
%   REAL path: when a trained network (from trainClassifier /
%   benchmark_backbones) is supplied, the image is resized to the net input,
%   normalized, and softmax probabilities come from predict().
%
%   MOCK path: if net is empty (no trained model), a deterministic pseudo-
%   probability is produced from image content — clearly synthetic and flagged
%   modelFile=''. It exists ONLY so the pipeline can run end-to-end before a
%   model exists; it is never presented as clinical output (AGENTS.md no-fake-AI).

    cfg = experiment_config();
    if nargin < 3 || isempty(params); params = cfg.classification; end

    % Use params for referThreshold if provided
    if isfield(params, 'referThreshold')
        referThreshold = params.referThreshold;
    else
        referThreshold = cfg.referThreshold;
    end

    if isempty(net)
        grading = mockGrading(image, cfg, referThreshold);
    else
        grading = realGrading(image, net, cfg, referThreshold);
    end
end

function grading = realGrading(image, net, cfg, referThreshold)
%REALGRADING  Predict 5-class softmax via the trained CNN.
    if ~isempty(net)
        % Ensure a usable imageDatastore-free array for predict.
        im = imresize(image, cfg.classification.classify.inputSize(1:2));
        im = single(im) / 255;
        im = reshape(im, [size(im,1) size(im,2) size(im,3) 1]);   % add batch dim
        score = predict(net, im);                 % 1x5 softmax
        rawProbs = double(score(1, :));
    else
        rawProbs = NaN(1, 5);
    end

    rawProbs = rawProbs / sum(rawProbs);         % guard: normalise to sum 1
    grade = find(rawProbs == max(rawProbs), 1) - 1;
    refIdx = cfg.classification.referIndex;      % grade>=2 -> idx 3..5
    referableProb = sum(rawProbs(refIdx:end));
    referable = grade >= referThreshold;          % decision on hard grade (Level 2+)

    grading = struct( ...
        'rawProbs',      rawProbs, ...
        'grade',         grade, ...
        'referableProb', referableProb, ...
        'referable',     referable, ...
        'modelFile',     getNetName(net, cfg));
end

function name = getNetName(net, cfg)
    if isa(net, 'nnet.cnn.LayerGraph'); name = 'layerGraph'; return; end
    if isprop(net, 'Name') && ~isempty(net.Name); name = net.Name; return; end
    if isfield(cfg.model, 'backbone') && ~isempty(cfg.model.backbone)
        name = sprintf('%s_dr_aptos.mat', cfg.model.backbone); return;
    end
    name = '(untitled network)';
end

function grading = mockGrading(image, cfg, referThreshold)
%MOCKGRADING  Deterministic pseudo-signal stand-in (no trained model). The
% mock is explicit: it is not a model and must not be cited as clinical output.
    m = cfg.mock;
    rng(m.seed, 'twister');

    g = mean(image(:, :, 2), 'all') / 255;
    base = [3.0, 0.8*exp(2*g), 0.5*exp(3*g), 0.3*exp(3.5*g), 0.2*exp(4*g)];
    rawProbs = base / sum(base);

    grade = find(rawProbs == max(rawProbs), 1) - 1;
    refIdx = cfg.classification.referIndex;
    referableProb = sum(rawProbs(refIdx:end));

    % Referable-DR threshold is LEVEL 2+ (docs/ARCHITECTURE.md §2 Stage 6).
    % Decision driven by the hard grade threshold; prob reported as evidence.
    referable = grade >= referThreshold;

    grading = struct( ...
        'rawProbs',      rawProbs, ...
        'grade',         grade, ...
        'referableProb', referableProb, ...
        'referable',     referable, ...
        'modelFile', '');   % no trained model in mock
end
