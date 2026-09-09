function grading = classifyImage(image, net, params)
%CLASSIFYIMAGE  Stage 6: DR severity grading, 5-class + referable-DR.
%
%   grading = classifyImage(image, net, params)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.4):
%     grading.rawProbs     1x5 double, P(grade 0..4), sums to 1
%     grading.grade        0..4 (argmax)
%     grading.referableProb P(grade >= 2)
%     grading.referable    referableProb >= cfg.referThreshold-based threshold
%
%   With a real trained net, net = the chosen backbone network and params = the
%   classification config. WITHOUT a trained model (Sprint 0), net may be empty:
%   the mock branch produces DETERMINISTIC PSEUDO-PROBABILITIES derived from
%   image content — clearly synthetic, seeded, and flagged model.available=false.
%   It exists ONLY to let the pipeline run end-to-end. It is NOT a trained model
%   and must never be presented as clinical output.
%
%   TODO(Sprint 2+): trainClassifier + benchmark_backbones select the real CNN;
%   replace the mock branch with predict() on the trained net.

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
        % Real inference path — implement in Sprint 2+:
        %   im  = preprocess for net.Layers(1).InputSize
        %   prob = predict(net, im); ...
        grading = mockGrading(image, cfg, referThreshold);   % placeholder until model exists
        grading.modelFile = '(real net supplied but inference TODO)';
    end
end

function grading = mockGrading(image, cfg, referThreshold)
    m = cfg.mock;
    rng(m.seed, 'twister');

    % Deterministic pseudo-signal: mean green channel luminance -> "disease-ness".
    g = mean(image(:, :, 2), 'all') / 255;

    % Weight probs toward higher grades for brighter (mock) images; keep sane.
    base = [3.0, 0.8*exp(2*g), 0.5*exp(3*g), 0.3*exp(3.5*g), 0.2*exp(4*g)];
    rawProbs = base / sum(base);

    grade = find(rawProbs == max(rawProbs), 1) - 1;       % 0..4 (argmax)
    refIdx = cfg.classification.referIndex;               % grade>=2 -> idx 3..5
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