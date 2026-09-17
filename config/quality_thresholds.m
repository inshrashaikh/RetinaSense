function q = quality_thresholds()
%QUALITY_THRESHOLDS  Image quality gate thresholds (config/quality_thresholds.m).
%
%   q = quality_thresholds()
%
%   Single source of truth for how assessQuality.m classifies an image as
%   good / borderline / ungradable based on per-metric scores (each 0..1).
%   Per-metric interpretation:
%     focus       -> higher is sharper
%     illumination-> higher is better-exposed
%     fovCoverage -> higher is more of the retina visible
%     artifacts   -> higher is cleaner (fewer glare/sat/clipping)
%
%   References: docs/ARCHITECTURE.md §2 Stage 1.
%
%   SOURCE OF TRUTH / OVERRIDE: the committed values below stand until
%   scripts/calibrate_quality_gate.m runs against a human-rated labeled subset
%   (data/manifests/quality_labels.csv) and writes a validated override to
%   qc.persist.overrideFile. When that file exists AND config/quality_calibration.m
%   applyOverride is true, its fields replace the committed defaults — TODO(Sprint 1).
%   Absent override, these defaults stand; nothing is auto-written or fabricated.

    q = struct();

    % Focus normalization divisor for assessQuality.m's Laplacian-variance
    % sharpness metric: focus = min(1, var(lap)/focusNormalizeVar).
    % Calibrated on real fundus data (APTOS 2019 + IDRiD resized to 1024px
    % working size): the data-driven value 0.005 maps an average-sharpness
    % fundus image to focus ~0.7 (vs the previous ad-hoc 0.02 which mapped
    % nearly every real image below the 0.25 ungradable threshold). The move
    % to config honours 'no hard-coded thresholds' — see TODO(Sprint 1).
    q.focusNormalizeVar = 0.005;

    % Any metric below 'ungradable' threshold => image is ungradable.
    q.metricLow  = [ ...   % rows: [metric key, ungradable threshold]
        {'focus',          0.25}; ...
        {'illumination',   0.20}; ...
        {'fovCoverage',    0.30}; ...
        {'artifacts',      0.30}];

    % Any metric below 'borderline' threshold (but >= ungradable) => borderline.
    q.metricMid  = [ ...
        {'focus',          0.55}; ...
        {'illumination',   0.50}; ...
        {'fovCoverage',    0.55}; ...
        {'artifacts',      0.50}];

    % Overall weighted combination thresholds (composite score 0..1).
    q.weights   = struct( ...
        'focus',        0.40, ...
        'illumination', 0.25, ...
        'fovCoverage',  0.20, ...
        'artifacts',    0.15);

    % Composite score >= goodScore => good (if no metric below borderline).
    q.goodScore      = 0.65;
    q.borderlineScore = 0.40;

    % ---- Calibration override (Sprint 1 harness) ----
    % scripts/calibrate_quality_gate.m persists a validated threshold set from
    % a real experiment on a human-rated subset. quality_thresholds_override()
    % returns that set when present + enabled; missing/corrupt/disabled always
    % falls back to the committed defaults above (the gate never breaks).
    ov = quality_thresholds_override();
    if ~isempty(ov)
        f = fieldnames(ov);
        for i = 1:numel(f)
            q.(f{i}) = ov.(f{i});
        end
    end
end

function ov = quality_thresholds_override()
%QUALITY_THRESHOLDS_OVERRIDE  Load the persisted calibrated threshold set.
    ov = struct();
    try
        qc = quality_calibration();
        if ~qc.applyOverride; return; end
        file = qc.persist.overrideFile;
        if ~exist(file, 'file'); return; end
        S = load(file, 'q');
        if ~isfield(S, 'q') || ~isstruct(S.q); return; end
        if ~all(isfield(S.q, {'focusNormalizeVar','metricLow','metricMid', ...
                'weights','goodScore','borderlineScore'}))
            return;   % incomplete override: keep committed defaults
        end
        ov = S.q;
    catch
        ov = struct();  % corrupt/inaccessible override must not break the gate
    end
end
