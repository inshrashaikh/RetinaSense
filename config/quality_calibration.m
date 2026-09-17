function qc = quality_calibration()
%QUALITY_CALIBRATION  Quality-gate calibration config (config/quality_calibration.m).
%
%   qc = quality_calibration()
%
%   Everything the Sprint 1 quality-gate calibration harness needs
%   (scripts/calibrate_quality_gate.m). All paths / grids / objective weights
%   live here, never in module code (AGENTS.md guardrail 2).
%
%   Labeled subset CSV schema (data/manifests/quality_labels.csv when present):
%     image,label[,kind]
%       image  = path relative to qc.imageRoot (e.g. '1\img_0003.png')
%       label  = good | borderline | ungradable   (human-rated gate truth)
%       kind   = human-rated | synthetic (optional provenance; default labelKind)
%
%   The harness is HONEST by construction: it only ever computes metrics from
%   real assessQuality() runs on the provided subset. If the subset file is
%   absent it raises RetinaSense:calibrateQualityGate:MissingLabeledSubset and
%   persists nothing (AGENTS.md guardrails 1/3). See TODO(Sprint 1) markers in
%   config/quality_thresholds.m and preprocessing/assessQuality.m.
%
%   References: docs/ARCHITECTURE.md §2 Stage 1, §4.1.

    % ---- Labeled subset ----
    qc.labeledSubsetPath = fullfile(paths().data.manifests, 'quality_labels.csv');
    qc.imageRoot         = paths().data.images;
    qc.labelKind         = 'human-rated';  % provenance of the subset labels

    % ---- Search grid over the gate thresholds ----
    % lowScales  : multiplier applied to every metricLow threshold (each capped
    %              strictly below its metricMid counterpart to keep the
    %              low < mid ordering assessQuality.classify() relies on).
    % goodDelta / borderlineDelta : additive offsets on the composite scores,
    %              enforced so 0 <= borderlineScore < goodScore <= 1.
    qc.grid = struct( ...
        'lowScales',        [0.8, 1.0, 1.2, 1.4], ...
        'goodDelta',        [-0.10, 0, 0.10], ...
        'borderlineDelta',  [-0.10, 0, 0.10]);

    % ---- Objective weights (minimised composite loss) ----
    %   falseRejectionRate : share of gradeable labels (good|borderline) the
    %                        gate wrongly flags ungradable (how low the better).
    %   ungradableCatchMiss : 1 - share of ungradable labels actually gated
    %                        ungradable (how low the better).
    %   agreementMiss : 1 - overall predicted-vs-labeled class agreement.
    qc.objective = struct( ...
        'agreementWeight',        1.0, ...
        'falseRejectionWeight',   1.0, ...
        'ungradableCatchWeight',  1.0, ...
        'borderlineMissWeight',   0.5);

    % ---- Persistence ----
    % metricsFile  : JSON audit trail of the real experiment ('' -> a
    %                timestamped file in outputDir). Committed output is the
    %                metrics JSON; the override artifact below is runtime state.
    % overrideFile : .mat with struct q = the chosen threshold set + provenance
    %                (written only when applyOverride). quality_thresholds()
    %                activates it when the file exists and applyOverride is true.
    qc.persist = struct( ...
        'outputDir',      fullfile(paths().output), ...
        'metricsFile',    '', ...
        'overrideFile',   fullfile(paths().data.models, 'quality_gate_calibration.mat'));
    qc.applyOverride = true;   % activate a persisted calibrated threshold set
end