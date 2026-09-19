function cfg = experiment_config()
%EXPERIMENT_CONFIG  Central thresholds and experiment settings for RetinaSense.
%
%   cfg = experiment_config()
%
%   ALL clinical/runtime thresholds and experiment parameters live here (and in
%   the sub-config builders it calls). Nothing is hard-coded across modules.
%   See config/quality_thresholds.m, config/preprocess_config.m,
%   config/classification_config.m for the grouped constants.
%
%   Backbone is benchmark-driven (docs/ARCHITECTURE.md §3.2); it is NOT pinned
%   until scripts/benchmark_backbones.m selects it. Until a model is chosen the
%   pipeline uses the mock; model.available=false.

    cfg = struct();

    % ---- Seed / reproducibility ----
    cfg.seed = 42;

    % ---- Quality gate thresholds ----
    cfg.quality = quality_thresholds();

    % ---- Image preprocessing (ingest / enhance / classify-input) ----
    cfg.preprocess = preprocess_config();

    % ---- Classification / DR grading ----
    cfg.classification = classification_config();

    % ---- Benchmark targets for backbone selection (SIH PS 26038) ----
    % These are TARGETS used only for DECISION RULES in
    % scripts/benchmark_backbones.m. They are never reported as achieved
    % metrics; the harness records whether they were actually met.
    cfg.benchmark = struct( ...
        'se', 0.90, ...    % referable sensitivity target
        'sp', 0.85, ...    % referable specificity target
        'tieBreak', 'size');   % 'size' | 'latency' among target-meeting backbones

    % ---- Retinal Analysis (advisory, Stage 5) ----
    cfg.analysis = analysis_config();

    % ---- Explainability ----
    cfg.explainability = struct( ...
        'layers',      '', ...   % selected from the benchmarked backbone below
        'note',        'Model attention - not proof of causality', ...
        'colormap',    'jet');

    % ---- Calibration & uncertainty / review routing ----
    cfg.calibration = struct( ...
        'temperatureMode', 'fit', ...   % 'fit' | 'fixed'; 'fit' needs validation logits
        'temperature',     1.0, ...     % used when mode == 'fixed'
        'confidenceLow',   0.80, ...    % below -> reviewRequired (FR-08)
        'uncertaintyHigh', 0.30, ...    % above -> reviewRequired
        'normEntropyMode', 'log5');     % normalized entropy denominator

    % Forced review: even if no threshold crossed, some policy flags review.
    cfg.review = struct( ...
        'autoApproveAbove', 0.90, ...   % confidence >= this -> autoRefer/autoClear
        'alwaysReview',     false);     % force human review for every case

    % ---- Reporting ----
    cfg.report = report_config();

    % ---- Referable DR threshold (Level 2+) ----
    cfg.referThreshold = 2;   % grade >= 2 is "referable DR" (config/classification_config)

    % ---- Mock flags (explicit opt-in only; screening uses the real model) ----
    cfg.mock = struct( ...
        'enabled', false, ...          % mock runs only via 'mock', true (tests/demo)
        'seed',    1, ...              % deterministic mock outputs
        'maxGradable', 0.85);          % mock: prob an image is graded 'good'

    % ---- Chosen backbone + benchmark result (filled by scripts/benchmark_backbones.m) ----
    cfg.model = struct( ...
        'backbone',  '', ...       % 'resnet50' | 'efficientnetb0' | '' (unset)
        'metrics',   struct(), ... % benchmark four-axis table (SE,SP,AUROC,latency,size)
        'targetsMet', false, ...   % honest benchmark outcome (not a gate)
        'available', false);       % true when a backbone is selected (record present);
                                   % artifact presence/validity enforced at load time

    cfg.model = loadModelRecord(cfg.model);   % reads data/models/backbone_benchmark.json

    % The shipped MATLAB ResNet-50 artifact is a dlnetwork whose final
    % convolutional feature layer is L4_2_relu3. Keep Grad-CAM tied to the
    % same benchmark-selected backbone and its actual layer names.
    if cfg.model.available && isfield(cfg.classification.train.featureLayerName, cfg.model.backbone)
        cfg.explainability.layers = cfg.classification.train.featureLayerName.(cfg.model.backbone);
    end
end

function model = loadModelRecord(model)
%LOADMODELRECORD  If a benchmark run has been recorded (scripts/
% benchmark_backbones.m -> data/models/backbone_benchmark.json), surface the
% chosen backbone + metrics into cfg.model. This is the single place a
% benchmark decision becomes visible to the rest of the pipeline.
    recFile = fullfile(paths().data.models, 'backbone_benchmark.json');
    if ~exist(recFile, 'file'); return; end        % no record yet (real model unavailable)
    try
        rec = jsondecode(fileread(recFile));
        model.backbone  = rec.chosenBackbone;
        % perBackbone is the supplementary four-axis table; a valid decision
        % record may omit it without invalidating the chosen backbone.
        if isfield(rec, 'perBackbone')
            model.metrics   = rec.perBackbone;
        end
        % 'available' = a backbone was actually chosen by the benchmark run.
        % It is decoupled from rec.targetsMet: the real trained artifact is
        % the screening default even while clinical targets are still being
        % reached. Artifact presence/validity is enforced at load time by
        % loadTrainedModel/loadCalibration (clear structured errors, no
        % silent mock fallback).
        model.available = ~isempty(rec.chosenBackbone);
        if isfield(rec, 'targetsMet')
            % Honest, non-gating record of the measurable outcome.
            model.targetsMet = rec.targetsMet;
        end
    catch
        % A corrupt/partial record must not break pipeline startup; leave the
        % model unavailable so callers can fall back to explicit mock only.
    end
end
