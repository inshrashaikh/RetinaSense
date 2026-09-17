function quality = assessQuality(working, params)
%ASSESSQUALITY  Stage 1: image quality assessment (IQA) - the entry gate.
%
%   quality = assessQuality(working, params)
%
%   working: HxWx3 uint8 working RGB image
%   params:  its threshold group (cfg.quality -> quality_thresholds(); may be
%            passed as '' to auto-load)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.1):
%     quality.score          double 0..1 (weighted composite)
%     quality.class          'good' | 'borderline' | 'ungradable'
%     quality.metrics        focus, illumination, fovCoverage, artifacts (0..1)
%     quality.failureReasons cellstr, e.g. {'focus','illumination'}
%     quality.recapture      struct reasonCode+instruction (set if ungradable)
%
%   This is the differentiator module (docs/ARCHITECTURE.md §3.1): classical
%   CV metrics, deterministic + explainable (no DL). The per-metric math here
%   is genuine plumbing; tuning the thresholds/weights against a small
%   human-rated subset is TODO(Sprint 1). This keeps the gate honest, not fake.

    if nargin < 2 || isempty(params); params = quality_thresholds(); end

    gray = rgb2gray(im2double(working));

    % ---- Metric 1: focus (variance of Laplacian, green channel) ----
    % Higher laplacian variance => sharper. Normalized to 0..1 by the
    % data-calibrated divisor (config/quality_thresholds.m focusNormalizeVar).
    lap = conv2(gray, [0 1 0; 1 -4 1; 0 1 0], 'same');
    focus = min(1, var(lap(:)) / params.focusNormalizeVar);

    % ---- Metric 2: illumination (luminance mean + saturation guard) ----
    lumMean = mean(gray(:));
    illum = max(0, min(1, 1 - abs(lumMean - 0.5) / 0.5));  % 0.5 luminance = ideal

    % ---- Metric 3: FOV coverage (non-dark fraction) ----
    fovCoverage = mean(gray(:) > 0.06);   % fraction of pixels = fundus, not void

    % ---- Metric 4: artifacts (clip / saturation / glare fraction) ----
    satFrac = mean(gray(:) > 0.985);
    darkFrac = mean(gray(:) < 0.01);
    artifacts = max(0, 1 - (satFrac + darkFrac));

    metrics = struct('focus', focus, 'illumination', illum, ...
                     'fovCoverage', fovCoverage, 'artifacts', artifacts);

    % ---- Rule-based classification against config thresholds ----
    [score, klass, failures] = classify(params, metrics);
    % NOTE: built field-by-field, NOT via struct(...) with the `failures` cell
    % value. struct() treats a cell array as a per-element value list, so a
    % non-scalar/empty cell would widen `quality` into a struct array (e.g. 0x0
    % for a 'good' image) and break the scalar 1x1 contract (ARCHITECTURE m4.1).
    quality = struct();
    quality.score          = score;
    quality.class          = klass;
    quality.metrics        = metrics;
    quality.failureReasons = failures;
    quality.recapture      = struct('reasonCode', '', 'instruction', '');

    if strcmp(klass, 'ungradable')
        % Delegate recapture guidance to recaptureFeedback (shared with Stage 2).
        r = recaptureFeedback(failures);
        quality.recapture = r;
    end

    % TODO(Sprint 1): calibrate thresholds/weights against a small human-rated
    % quality subset; add reported false-rejection rate (docs/ARCHITECTURE.md §2
    % Stage 1 metric). Harness ready: scripts/calibrate_quality_gate.m + config/
    % quality_calibration.m. Until a labeled subset exists in data/manifests/
    % quality_labels.csv the committed quality_thresholds() defaults stand and
    % this gate stays honest (AGENTS.md #1/#3).
end

function [score, klass, failures] = classify(params, metrics)
    names = fieldnames(metrics);
    lowFail = {};
    midFail = {};
    for i = 1:numel(names)
        m = names{i};
        low = thresholdFor(params.metricLow, m);
        mid = thresholdFor(params.metricMid, m);
        if metrics.(m) < low
            lowFail{end+1} = m; %#ok<AGROW>  (bounded 4-element list)
        elseif metrics.(m) < mid
            midFail{end+1} = m; %#ok<AGROW>
        end
    end

    score = params.weights.focus * metrics.focus + ...
            params.weights.illumination * metrics.illumination + ...
            params.weights.fovCoverage * metrics.fovCoverage + ...
            params.weights.artifacts * metrics.artifacts;

    if ~isempty(lowFail)
        klass    = 'ungradable';
        failures = lowFail;             % drives recaptureFeedback (Stage 2)
    elseif score < params.borderlineScore
        % Composite floor: uniformly mediocre overall quality is still
        % ungradable even if no single metric crosses its 'low' threshold.
        klass    = 'ungradable';
        failures = worstMetric(metrics);
    elseif ~isempty(midFail) || score < params.goodScore
        % Borderline: report which metric(s) fell short. If no individual
        % metric breached the borderline band but the composite score is low,
        % flag it explicitly so failureReasons is never silently empty while
        % the image is not 'good' (contract: "why not good; empty if good").
        if isempty(midFail)
            klass    = 'borderline';
            failures = {'composite'};
        else
            klass    = 'borderline';
            failures = midFail;
        end
    else
        klass    = 'good';
        failures = {};
    end
end

function names = worstMetric(metrics)
    mnames = fieldnames(metrics);
    worst  = Inf;
    names  = {};
    for i = 1:numel(mnames)
        v = metrics.(mnames{i});
        if v < worst
            worst = v;
            names = {mnames{i}};
        elseif v == worst && ~isempty(names)
            names{end+1} = mnames{i}; %#ok<AGROW>  tie -> multiple reasons
        end
    end
end

function t = thresholdFor(table, key)
    t = 0;
    for i = 1:size(table, 1)
        if strcmp(table{i, 1}, key); t = table{i, 2}; return; end
    end
end