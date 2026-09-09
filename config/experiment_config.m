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
%   until scripts/benchmark_backbones.m selects it. In Sprint 0 the pipeline
%   uses the mock; model.available=false.

    cfg = struct();

    % ---- Seed / reproducibility ----
    cfg.seed = 42;

    % ---- Quality gate thresholds ----
    cfg.quality = quality_thresholds();

    % ---- Image preprocessing (ingest / enhance / classify-input) ----
    cfg.preprocess = preprocess_config();

    % ---- Classification / DR grading ----
    cfg.classification = classification_config();

    % ---- Retinal Analysis (advisory, Stage 5) ----
    cfg.analysis = analysis_config();

    % ---- Explainability ----
    cfg.explainability = struct( ...
        'layers',      '', ...   % e.g. 'activation_40_relu' (set post-benchmark)
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

    % ---- Mock / Sprint-0 flags ----
    cfg.mock = struct( ...
        'enabled', true, ...           % true -> run mock modules, no trained models
        'seed',    1, ...              % deterministic mock outputs
        'maxGradable', 0.85);          % mock: prob an image is graded 'good'

    % ---- Chosen backbone + benchmark result (filled by scripts/benchmark_backbones.m) ----
    cfg.model = struct( ...
        'backbone',  '', ...       % 'resnet50' | 'efficientnetb0' | '' (unset)
        'metrics',   struct(), ... % benchmark four-axis table (SE,SP,AUROC,latency,size)
        'available', false);       % true only after training + artifacts exist
end
