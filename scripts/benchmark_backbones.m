function results = benchmark_backbones()
%BENCHMARK_BACKBONES  ResNet-50 vs EfficientNet-B0 selection harness.
%
%   results = benchmark_backbones()
%
%   Trains both ImageNet-pretrained backbones on APTOS 2019 and reports the
%   four-axis comparison (docs/ARCHITECTURE.md §3.2, §2 Stage 6 metric):
%     referable SE / SP   (primary SIH target >90% / >85%)
%     AUROC               (referable)
%     inference latency   (prototype hardware)
%     model size          (memory/storage)
%
%   Selection rule (not hard-coded to any backbone):
%     1. Among backbones meeting BOTH clinical targets (SE>tSe, SP>tSp),
%        pick the cheaper/faster one.
%     2. Otherwise pick the one with highest referable AUROC and RECORD a
%        flag that the clinical targets were NOT met (honest reporting).
%
%   Records the chosen backbone + per-backbone metrics to
%   data/models/backbone_benchmark.json, which config/experiment_config.m
%   loads into cfg.model (backbone, metrics, available).
%
%   HONESTY (AGENTS.md): with no APTOS rows in the manifest or no Deep
%   Learning Toolbox, this raises a clear error. It never fabricates a
%   backbone decision or any metric.

    cfg = experiment_config();
    tc  = cfg.classification.train;
    targets = cfg.benchmark;               % SE/SP targets + tie-break preference

    data = prepareClassifierData();         % throws if manifest is schema-only
    if data.n_train < 10
        raiseError('benchmark_backbones', 'InsufficientData', ...
            'Benchmark needs real APTOS train data (got %d rows).', data.n_train);
    end

    rows = struct();
    for i = 1:numel(tc.backboneCandidates)
        b = tc.backboneCandidates{i};
        logMessage('info', 'benchmark_backbones', sprintf('Backbone: %s', b));

        net = trainClassifier(b, 'manifest', data.manifestFile, ...
                              'maxEpochs', tc.maxEpochs);
        ev  = evaluateClassifier(net, data.val);

        % ---- Inference latency: mean over a dev batch (prototype hardware) ----
        lat = measureLatency(net, data.val, cfg);

        % ---- Model size: bytes on disk of the trained artifact ----
        modelFile = fullfile(paths().data.models, sprintf('%s_dr_aptos.mat', b));
        sz = dir(modelFile);
        sizeBytes = sz.bytes;

        rows.(b) = struct( ...
            'referableSensitivity', ev.referableSensitivity, ...
            'referableSpecificity', ev.referableSpecificity, ...
            'aucReferable',         ev.aucReferable, ...
            'accuracy',             ev.accuracy, ...
            'quadraticKappa',       ev.quadraticKappa, ...
            'latencyMs',            lat, ...
            'sizeBytes',            sizeBytes, ...
            'meetsTargets',         ev.referableSensitivity >= targets.se && ...
                                    ev.referableSpecificity >= targets.sp);
    end

    % ---- Selection ----
    bnames = tc.backboneCandidates;
    meet = cellfun(@(n) rows.(n).meetsTargets, bnames);
    if any(meet)
        % Prefer the cheaper/faster among target-meeting backbones.
        cand = bnames(meet);
        best = cand{1};
        for i = 2:numel(cand)
            if rows.(cand{i}).sizeBytes < rows.(best).sizeBytes
                best = cand{i};
            end
        end
        targetsMet = true;
    else
        % No backbone meets clinical targets: select by best referable AUROC,
        % and record that targets were not met (honest, no over-claim).
        aucs = cellfun(@(n) rows.(n).aucReferable, bnames);
        [~, ix] = max(aucs);
        best = bnames{ix};
        targetsMet = false;
    end

    record = struct( ...
        'chosenBackbone', best, ...
        'targetsMet',     targetsMet, ...
        'perBackbone',    rows, ...
        'targets',        struct('se', targets.se, 'sp', targets.sp), ...
        'timestamp',      datestr(now, 'yyyy-mm-ddTHH:MM:SS'));

    saveBenchmarkRecord(record);
    logMessage('info', 'benchmark_backbones', ...
        sprintf('Chosen backbone: %s (targetsMet=%d)', best, targetsMet));

    % Also print the four-axis table.
    fprintf('\n=== Backbone benchmark ===\n');
    fprintf('%-16s %7s %7s %7s %8s %10s %10s\n', 'backbone', 'SE', 'SP', 'AUROC', 'acc', 'lat(ms)', 'size(MB)');
    for i = 1:numel(bnames)
        b = bnames{i};
        r = rows.(b);
        fprintf('%-16s %7.1f %7.1f %7.3f %8.3f %10.1f %10.2f\n', b, ...
            100*r.referableSensitivity, 100*r.referableSpecificity, r.aucReferable, ...
            r.accuracy, r.latencyMs, r.sizeBytes/1e6);
    end
    fprintf('=== Chosen: %s (targetsMet=%d) ===\n\n', best, targetsMet);

    results = record;
end

function lat = measureLatency(net, valDs, cfg)
%MEASURELATENCY  Mean inference ms over up to 32 validation images.
    if isempty(valDs) || numel(valDs.Files) == 0
        lat = NaN; return;
    end
    n = min(32, numel(valDs.Files));
    au = augmentedImageDatastore(cfg.classification.classify.inputSize(1:2), valDs);
    t0 = tic;
    for i = 1:n
        predict(net, read(au));
    end
    lat = toc(t0) / n * 1e3;
end

function saveBenchmarkRecord(record)
%SAVEBENCHMARKRECORD  Persist benchmark choice to JSON (consumed by
% config/experiment_config.m -> cfg.model).
    p = paths();
    recDir = p.data.models;
    if ~exist(recDir, 'dir'); mkdir(recDir); end
    recFile = fullfile(recDir, 'backbone_benchmark.json');
    s = jsonencode(record);
    fid = fopen(recFile, 'w');
    if fid > 0
        fprintf(fid, '%s', s);
        fclose(fid);
        logMessage('info', 'benchmark_backbones', sprintf('Recorded -> %s', recFile));
    else
        logMessage('warn', 'benchmark_backbones', ...
            'Could not write benchmark record to %s', recFile);
    end
end