function metrics = loadMetrics(cfg)
%LOADMETRICS  Load persisted real evaluation metrics (§8).
%
%   metrics = loadMetrics(cfg)
%
%   Loads the metrics artifact written by evaluation/saveMetrics.m as
%
%       data/models/<backbone>_metrics.mat      (paths().data.models)
%
%   where <backbone> = cfg.model.backbone (benchmark-driven). Returns the
%   struct produced by a real experiment run (evaluation/metrics.m contract).
%
%   Failures (AGENTS.md raiseError convention):
%     RetinaSense:loadMetrics:MissingModel     no backbone selected
%     RetinaSense:loadMetrics:MissingArtifact  artifact file does not exist
%     RetinaSense:loadMetrics:InvalidArtifact  unreadable / no metrics variable
%     RetinaSense:loadMetrics:InvalidMetrics   stored value not a valid contract

    validateattributes(cfg, {'struct'}, {'scalar'}, 'loadMetrics', 'cfg', 1);

    backbone = cfg.model.backbone;
    if isempty(backbone)
        raiseError('loadMetrics', 'MissingModel', ...
            'No backbone selected (cfg.model.backbone is empty). Run benchmark_backbones first.');
    end

    artFile = fullfile(paths().data.models, sprintf('%s_metrics.mat', backbone));
    if ~exist(artFile, 'file')
        raiseError('loadMetrics', 'MissingArtifact', ...
            'Metrics artifact not found: %s', artFile);
    end

    try
        S = load(artFile);
    catch ME
        raiseError('loadMetrics', 'InvalidArtifact', ...
            'Failed to load metrics artifact %s: %s', artFile, ME.message);
    end

    if ~isfield(S, 'metrics')
        raiseError('loadMetrics', 'InvalidArtifact', ...
            'Metrics artifact %s does not contain variable ''metrics''.', artFile);
    end

    metrics = S.metrics;
    if ~isMetricsContract(metrics)
        raiseError('loadMetrics', 'InvalidMetrics', ...
            'Metrics artifact %s does not hold a valid evaluation/metrics.m contract.', artFile);
    end
end

function tf = isMetricsContract(m)
    req = {'n', 'confusion', 'accuracy', ...
           'perClassSensitivity', 'perClassSpecificity', ...
           'referableSensitivity', 'referableSpecificity', ...
           'aucReferable', 'quadraticKappa', 'ece'};
    for i = 1:numel(req)
        if ~isfield(m, req{i})
            tf = false; return;
        end
    end

    if ~(isnumeric(m.n) && isscalar(m.n) && isfinite(m.n) && m.n >= 1)
        tf = false; return;
    end
    if ~(isnumeric(m.accuracy) && isscalar(m.accuracy) && isfinite(m.accuracy) ...
            && m.accuracy >= 0 && m.accuracy <= 1)
        tf = false; return;
    end
    for f = {'referableSensitivity', 'referableSpecificity'}
        v = m.(f{1});
        if ~(isnumeric(v) && isscalar(v) && isfinite(v) && v >= 0 && v <= 1)
            tf = false; return;
        end
    end
    if ~isnumeric(m.confusion) || ~isequal(size(m.confusion), [5 5])
        tf = false; return;
    end
    a = m.aucReferable;
    if ~(isnumeric(a) && isscalar(a) && ...
            (isnan(a) || (isfinite(a) && a >= 0 && a <= 1)))
        tf = false; return;
    end
    if ~(isnumeric(m.quadraticKappa) && isscalar(m.quadraticKappa) && isfinite(m.quadraticKappa))
        tf = false; return;
    end
    if ~(isnumeric(m.ece) && isscalar(m.ece) && isfinite(m.ece) && m.ece >= 0)
        tf = false; return;
    end
    tf = true;
end