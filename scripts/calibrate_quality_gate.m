function result = calibrate_quality_gate(varargin)
%CALIBRATE_QUALITY_GATE  Calibrate the quality-gate thresholds on a labeled subset.
%
%   result = calibrate_quality_gate()                                   % from config
%   result = calibrate_quality_gate('subsetPath', P, 'override', false) % test/dry-run
%
%   HONEST EXPERIMENT (AGENTS.md guardrails 1/3): this computes REAL metrics by
%   running preprocessing/assessQuality.m over every image of the labeled
%   subset, then picks the config/quality_calibration.m grid point with the
%   best objective. It NEVER fabricates labels, metrics, or thresholds.
%
%   Labeled subset CSV (schema in config/quality_calibration.m):
%       image,label[,kind]
%         image = path relative to imageRoot; label in {good,borderline,ungradable}
%         kind  = 'human-rated' | 'synthetic' (provenance; default labelKind)
%
%   Behavior:
%     * subset file missing        -> raises RetinaSense:calibrateQualityGate:
%                                       MissingLabeledSubset, persists NOTHING.
%     * any image missing          -> raises ...:MissingImages, persists nothing.
%     * invalid label read         -> raises ...:BadLabel, persists nothing.
%     * otherwise                  -> persists the real baseline + chosen metrics
%                                     to a JSON audit trail (outputDir), and when
%                                     'override' is true writes the chosen
%                                     threshold set to qc.persist.overrideFile
%                                     (activated by config/quality_thresholds.m).
%
%   Name-value options (all optional; defaults from config/quality_calibration.m):
%     'subsetPath'   path to the labeled-subset CSV
%     'imageRoot'    root under which CSV image paths resolve
%     'outDir'       directory for the metrics JSON
%     'metricsFile'  explicit metrics JSON path ('' -> timestamped in outDir)
%     'overrideFile' explicit override .mat path ('' -> config default)
%     'override'     logical: persist the chosen threshold set (default config)
%     'labelKind'    provenance of the subset labels
%
%   References: docs/ARCHITECTURE.md §2 Stage 1, §4.1; config/quality_thresholds.m
%               TODO(Sprint 1).

    o = parseOptions(varargin);

    qc = quality_calibration();
    qc = mergeOptionOverrides(qc, o);

    % ---- Load + validate the labeled subset (real labels only) ----
    rows = loadLabeledSubset(qc.labeledSubsetPath, qc.imageRoot, qc.labelKind);
    if numel(rows.q) == 0
        raiseError('calibrateQualityGate', 'EmptyLabeledSubset', ...
            'Labeled subset %s contains no rows.', qc.labeledSubsetPath);
    end

    [rows, resolved] = resolveImagePaths(rows, qc.imageRoot);
    if ~isempty(resolved.missing)
        raiseError('calibrateQualityGate', 'MissingImages', ...
            '%d image(s) referenced by %s were not found (first: %s).', ...
            numel(resolved.missing), qc.labeledSubsetPath, resolved.missing{1});
    end

    % ---- Real scoring pass (baseline = current effective thresholds) ----
    baselineQ = quality_thresholds();
    preds = scoreAll(rows.q, baselineQ);
    baselineMetrics = gateMetrics(preds, rows.label);
    baselineLoss    = objectiveLoss(baselineMetrics, qc.objective);

    % ---- Grid search over config-driven threshold candidates ----
    best    = struct('loss', Inf, 'q', [], 'metrics', struct(), 'preds', []);
    nGrid   = numel(qc.grid.lowScales) * numel(qc.grid.goodDelta) * ...
              numel(qc.grid.borderlineDelta);
    gridRow = 1;
    gridResults = repmat(struct('lowScale', NaN, 'goodDelta', NaN, ...
        'borderlineDelta', NaN, 'loss', NaN, 'agreement', NaN), nGrid, 1);
    for s = 1:numel(qc.grid.lowScales)
        for g = 1:numel(qc.grid.goodDelta)
            for b = 1:numel(qc.grid.borderlineDelta)
                candQ = makeCandidate(baselineQ, qc.grid.lowScales(s), ...
                    qc.grid.goodDelta(g), qc.grid.borderlineDelta(b));
                candPreds = scoreAll(rows.q, candQ);
                candMet  = gateMetrics(candPreds, rows.label);
                candLoss = objectiveLoss(candMet, qc.objective);
                gridResults(gridRow) = struct( ...
                    'lowScale', qc.grid.lowScales(s), ...
                    'goodDelta', qc.grid.goodDelta(g), ...
                    'borderlineDelta', qc.grid.borderlineDelta(b), ...
                    'loss', candLoss, 'agreement', candMet.agreement);
                if ~isnan(candLoss) && candLoss < best.loss
                    best = struct('loss', candLoss, 'q', candQ, ...
                        'metrics', candMet, 'preds', {candPreds});
                end
                gridRow = gridRow + 1;
            end
        end
    end

    % ---- Persist the real metrics + (optionally) the chosen threshold set ----
    if isempty(best.q)
        raiseError('calibrateQualityGate', 'NoCandidate', ...
            'No candidate threshold set survived the search grid.');
    end

    metricsFile = writeMetricsJson(rows, baselineQ, baselineMetrics, baselineLoss, ...
        best, gridResults, nGrid, qc);
    overrideWritten = false;
    if qc.applyOverride
        writeOverride(best.q, metricsFile, qc.persist.overrideFile);
        overrideWritten = true;
    end

    result = struct( ...
        'subsetPath',      qc.labeledSubsetPath, ...
        'labelKind',       qc.labelKind, ...
        'nImages',         numel(rows.q), ...
        'labelCounts',     jsonable(rows.labelCounts), ...
        'baselineQ',       thresholdSetJsonable(baselineQ), ...
        'baselineMetrics', jsonable(baselineMetrics), ...
        'baselineLoss',    baselineLoss, ...
        'chosenQ',         thresholdSetJsonable(best.q), ...
        'chosenMetrics',   jsonable(best.metrics), ...
        'chosenLoss',      best.loss, ...
        'metricsFile',     metricsFile, ...
        'overrideFile',    qc.persist.overrideFile, ...
        'overrideWritten', overrideWritten, ...
        'selected',        best.q);

    logMessage('info', 'CALIBRATE', sprintf( ...
        'Quality gate calibrated on %d labeled images: agreement=%.3f, falseRejection=%.3f, loss=%.4f', ...
        numel(rows.q), best.metrics.agreement, best.metrics.falseRejectionRate, best.loss));
    if overrideWritten
        logMessage('info', 'CALIBRATE', sprintf( ...
            'Chosen thresholds written to %s (activated by quality_thresholds()).', ...
            qc.persist.overrideFile));
    else
        logMessage('warn', 'CALIBRATE', ...
            'Override persistence disabled; metrics JSON is the audit trail only.');
    end
end

% =========================================================================
%  Option handling
% =========================================================================

function o = parseOptions(args)
    o = struct('subsetPath', '', 'imageRoot', '', 'outDir', '', ...
        'metricsFile', '', 'overrideFile', '', 'override', [], 'labelKind', '');
    i = 1;
    while i <= numel(args)
        key = lower(char(args{i}));
        if i + 1 > numel(args)
            raiseError('calibrateQualityGate', 'BadArgs', ...
                'Missing value for option %s.', key);
        end
        val = args{i+1};
        switch key
            case 'subsetpath';   o.subsetPath   = char(val);
            case 'imageroot';    o.imageRoot    = char(val);
            case 'outdir';       o.outDir       = char(val);
            case 'metricsfile';  o.metricsFile  = char(val);
            case 'overridefile'; o.overrideFile = char(val);
            case 'override';     o.override     = logical(val);
            case 'labelkind';    o.labelKind    = char(val);
            otherwise
                raiseError('calibrateQualityGate', 'BadArgs', ...
                    'Unrecognized option %s.', key);
        end
        i = i + 2;
    end
end

function qc = mergeOptionOverrides(qc, o)
    if ~isempty(o.subsetPath);   qc.labeledSubsetPath  = o.subsetPath;  end
    if ~isempty(o.imageRoot);    qc.imageRoot           = o.imageRoot;   end
    if ~isempty(o.outDir);       qc.persist.outputDir   = o.outDir;      end
    if ~isempty(o.metricsFile);  qc.persist.metricsFile = o.metricsFile; end
    if ~isempty(o.overrideFile); qc.persist.overrideFile= o.overrideFile;end
    if ~isempty(o.override);     qc.applyOverride       = o.override;    end
    if ~isempty(o.labelKind);    qc.labelKind           = o.labelKind;   end
end

% =========================================================================
%  Labeled subset loading + image resolution
% =========================================================================

function rows = loadLabeledSubset(subsetPath, imageRoot, labelKind)
%LOADLABELEDSUBSET  Read the labeled-subset CSV as a validated struct array.
%   rows.q    : image file paths (absolute)
%   rows.label: cellstr of {good,borderline,ungradable}
%   rows.counts: per-class counts
    if ~exist(subsetPath, 'file')
        raiseError('calibrateQualityGate', 'MissingLabeledSubset', ...
            ['No labeled quality subset at %s. Add data/manifests/quality_labels.csv ' ...
            '(schema in config/quality_calibration.m) before calibrating; ' ...
            'nothing is fabricated in its absence.'], subsetPath);
    end
    try
        T = readtable(subsetPath);
    catch ME
        raiseError('calibrateQualityGate', 'BadCsv', ...
            'Could not read labeled subset %s: %s', subsetPath, ME.message);
    end
    if ~all(ismember({'image', 'label'}, T.Properties.VariableNames))
        raiseError('calibrateQualityGate', 'BadSchema', ...
            'Labeled subset %s must have columns image,label[,kind].', subsetPath);
    end

    classNames = {'good', 'borderline', 'ungradable'};
    qs      = strings(height(T), 1);
    labels  = strings(height(T), 1);
    kinds   = strings(height(T), 1);
    for i = 1:height(T)
        qs(i)    = string(char(T.image(i)));
        lab      = lower(string(char(T.label(i))));
        if ~any(strcmp(lab, classNames))
            raiseError('calibrateQualityGate', 'BadLabel', ...
                'Row %d of %s: unrecognized label ''%s'' (expected good|borderline|ungradable).', ...
                i, subsetPath, char(lab));
        end
        labels(i) = lab;
        kinds(i)  = labelKind;
        if ismember('kind', T.Properties.VariableNames)
            k = char(T.kind(i));
            if ~isempty(k) && ~strcmpi(k, 'NA')
                kl = lower(string(k));
                if ~(strcmp(kl, 'human-rated') || strcmp(kl, 'synthetic'))
                    raiseError('calibrateQualityGate', 'BadLabel', ...
                        'Row %d of %s: unrecognized kind ''%s'' (expected human-rated|synthetic).', ...
                        i, subsetPath, char(kl));
                end
                kinds(i) = kl;
            end
        end
    end

    rows = struct('q', {cellfun(@char, cellstr(qs), 'UniformOutput', false)}, ...
        'label', {cellstr(labels)}, 'kind', {cellstr(kinds)});

    counts = struct('good', 0, 'borderline', 0, 'ungradable', 0);
    for i = 1:numel(rows.label)
        counts.(rows.label{i}) = counts.(rows.label{i}) + 1;
    end
    rows.labelCounts = counts;
end

function [rows, resolved] = resolveImagePaths(rows, imageRoot)
%RESOLVEIMAGEPATHS  Turn CSV-relative paths into absolute, verified paths.
    missing = {};
    absPaths = cell(size(rows.q));
    for i = 1:numel(rows.q)
        p = rows.q{i};
        if ~isempty(p) && (exist(p, 'file') == 2)
            absPaths{i} = p;
        else
            cand = fullfile(imageRoot, p);
            if exist(cand, 'file') == 2
                absPaths{i} = cand;
            else
                missing{end+1} = p; %#ok<AGROW>
            end
        end
    end
    rows.q = absPaths;
    resolved = struct('missing', {missing}); % field -> the missing-path CELL itself
end

% =========================================================================
%  Real scoring + metrics
% =========================================================================

function preds = scoreAll(paths, q)
%SCOREALL  Real per-image gate classification under threshold set q.
    preds = cell(size(paths));
    for i = 1:numel(paths)
        try
            im  = imread(paths{i});
            qu  = assessQuality(im, q);
            preds{i} = qu.class;
        catch ME
            raiseError('calibrateQualityGate', 'ScoringFailed', ...
                'assessQuality failed on %s: %s', paths{i}, ME.message);
        end
    end
end

function m = gateMetrics(pred, label)
%GATEMETRICS  REAL agreement metrics of the gate vs the labeled subset.
%   NaN marks a metric not computable because of an absent class in the subset
%   (e.g. no 'ungradable' rows -> ungradableCatch is NaN, never invented).
    pred  = pred(:);
    label = label(:);
    n     = numel(pred);
    m = struct( ...
        'n', n, ...
        'agreement', mean(strcmp(pred, label)), ...
        'falseRejectionRate',  NaN, ...
        'ungradableCatch',     NaN, ...
        'borderlineMiss',      NaN, ...
        'perClassAgreement',   struct('good', NaN, 'borderline', NaN, 'ungradable', NaN));

    gradeable    = strcmp(label, 'good') | strcmp(label, 'borderline');
    if any(gradeable)
        m.falseRejectionRate = mean(...
            strcmp(pred(gradeable), 'ungradable'));
    end
    ungr = strcmp(label, 'ungradable');
    if any(ungr)
        m.ungradableCatch = mean(strcmp(pred(ungr), 'ungradable'));
    end
    bord = strcmp(label, 'borderline');
    if any(bord)
        m.borderlineMiss = mean(~strcmp(pred(bord), 'borderline'));
    end
    for cls = {'good', 'borderline', 'ungradable'}
        c = cls{1};
        idx = strcmp(label, c);
        if any(idx)
            m.perClassAgreement.(c) = mean(strcmp(pred(idx), c));
        end
    end
end

function loss = objectiveLoss(m, obj)
%OBJECTIVELOSS  Config-weighted composite (lower is better), computed only over
%   the metric terms ACTUALLY computable from the subset (absent-class terms
%   contribute nothing, never a favourite 0). Loss stays comparable because the
%   used-weight sum normalizes it.
    terms = {
        'agreementMiss',      1 - m.agreement,              obj.agreementWeight;
        'falseRejectionRate', m.falseRejectionRate,         obj.falseRejectionWeight;
        'ungradableCatchMiss', 1 - m.ungradableCatch,       obj.ungradableCatchWeight;
        'borderlineMiss',     m.borderlineMiss,             obj.borderlineMissWeight};
    usedW = 0; loss = 0;
    for i = 1:size(terms, 1)
        if ~isnan(terms{i, 2})
            w = terms{i, 3};
            loss = loss + w * terms{i, 2};
            usedW = usedW + w;
        end
    end
    if usedW == 0
        loss = 1;   % no computable term: degenerate subset, penalize heavily
    else
        loss = loss / usedW;
    end
end

% =========================================================================
%  Candidate threshold construction (config-driven grid)
% =========================================================================

function cand = makeCandidate(base, lowScale, goodDelta, borderlineDelta)
%MAKECANDIDATE  Candidate threshold set from the base, honoring the ordering
%   constraints assessQuality.classify() relies on (low < mid, bScore < gScore).
    cand = base;
    for i = 1:size(cand.metricLow, 1)
        key = cand.metricLow{i, 1};
        mid = thresholdFor(cand.metricMid, key);
        low = cand.metricLow{i, 2} * lowScale;
        cand.metricLow{i, 2} = min(low, mid * 0.99);
    end
    cand.goodScore = clampScore(base.goodScore + goodDelta, 0.05, 0.99);
    cand.borderlineScore = clampScore(...
        min(base.borderlineScore + borderlineDelta, cand.goodScore - 0.01), ...
        0.01, cand.goodScore - 0.01);
end

function v = clampScore(v, lo, hi)
    v = min(hi, max(lo, v));
end

function t = thresholdFor(table, key)
    t = 0;
    for i = 1:size(table, 1)
        if strcmp(table{i, 1}, key); t = table{i, 2}; return; end
    end
end

function s = jsonable(q)
%JSONABLE  Recursively keep numeric/logical/char/struct fields for JSON output
%   (cell fields - e.g. the metric threshold tables - use thresholdSetJsonable).
    s = struct();
    keep = fieldnames(q);
    for i = 1:numel(keep)
        v = q.(keep{i});
        if isstruct(v)
            s.(keep{i}) = jsonable(v);
        elseif isnumeric(v) || islogical(v) || ischar(v)
            s.(keep{i}) = v;
        end
    end
end

function s = thresholdSetJsonable(q)
%THRESHOLDSETJSONABLE  Plain-struct serialization of a quality_thresholds set
%   (metricLow/metricMid are cell tables -> per-metric structs).
    s = struct( ...
        'focusNormalizeVar', q.focusNormalizeVar, ...
        'metricLow',         thresholdTableToStruct(q.metricLow), ...
        'metricMid',         thresholdTableToStruct(q.metricMid), ...
        'weights',           struct( ...
            'focus',        q.weights.focus, ...
            'illumination', q.weights.illumination, ...
            'fovCoverage',  q.weights.fovCoverage, ...
            'artifacts',    q.weights.artifacts), ...
        'goodScore',         q.goodScore, ...
        'borderlineScore',   q.borderlineScore);
end

function s = thresholdTableToStruct(table)
    s = struct();
    for i = 1:size(table, 1)
        s.(table{i, 1}) = table{i, 2};
    end
end

% =========================================================================
%  Persistence
% =========================================================================

function metricsFile = writeMetricsJson(rows, baselineQ, baselineMetrics, ...
    baselineLoss, best, gridResults, nGrid, qc)
%WRITEMETRICSJSON  Persist the audit-trail JSON of the real experiment.
    if isempty(qc.persist.metricsFile)
        ts = datestr(now, 'yyyymmdd_HHMMSS');
        qc.persist.metricsFile = fullfile(qc.persist.outputDir, ...
            sprintf('quality_gate_calibration_%s.json', ts));
    end
    outDir = fileparts(qc.persist.metricsFile);
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    payload = struct( ...
        'kind',          'real-experiment', ...
        'generatedAt',   datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
        'experiment',    'quality-gate calibration (Sprint 1 harness)', ...
        'subsetPath',    qc.labeledSubsetPath, ...
        'labelKind',     qc.labelKind, ...
        'nImages',       numel(rows.q), ...
        'labelCounts',   jsonable(rows.labelCounts), ...
        'baseline',      struct( ...
            'thresholds', thresholdSetJsonable(baselineQ), ...
            'metrics',    jsonable(baselineMetrics), ...
            'loss',       baselineLoss), ...
        'grid',          struct( ...
            'lowScales',      qc.grid.lowScales, ...
            'goodDelta',      qc.grid.goodDelta, ...
            'borderlineDelta', qc.grid.borderlineDelta, ...
            'nCandidates',    nGrid, ...
            'candidates',     gridResults, ...
            'best',           struct( ...
                'chosenThresholds', thresholdSetJsonable(best.q), ...
                'metrics',          jsonable(best.metrics), ...
                'loss',             best.loss)), ...
        'note',          'Metrics computed by running assessQuality() over the labeled subset. No fabricated labels/results. thresholdOverride is applied by config/quality_thresholds.m when present+enabled.');

    fid = fopen(qc.persist.metricsFile, 'w');
    if fid <= 0
        raiseError('calibrateQualityGate', 'WriteFailed', ...
            'Could not write metrics JSON to %s.', qc.persist.metricsFile);
    end
    try
        fwrite(fid, jsonencode(payload, 'PrettyPrint', true));
    catch ME
        fclose(fid);
        raiseError('calibrateQualityGate', 'WriteFailed', ...
            'Could not serialize metrics JSON: %s', ME.message);
    end
    fclose(fid);
    metricsFile = qc.persist.metricsFile;
    logMessage('info', 'CALIBRATE', sprintf('Metrics JSON: %s', metricsFile));
end

function writeOverride(q, metricsFile, overrideFile)
%WRITEOVERRIDE  Persist the chosen threshold set for the gate to consume.
    outDir = fileparts(overrideFile);
    if ~exist(outDir, 'dir'); mkdir(outDir); end
    q = struct( ...
        'focusNormalizeVar', q.focusNormalizeVar, ...
        'metricLow',         q.metricLow, ...
        'metricMid',         q.metricMid, ...
        'weights',           q.weights, ...
        'goodScore',         q.goodScore, ...
        'borderlineScore',   q.borderlineScore);
    source = struct( ...
        'script', 'scripts/calibrate_quality_gate.m', ...
        'metricsFile', metricsFile, ...
        'writtenAt', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    save(overrideFile, 'q', 'source');
end