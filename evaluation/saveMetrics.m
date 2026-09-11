function filepath = saveMetrics(metrics, backbone)
%SAVEMETRICS  Persist REAL evaluation/benchmark metrics (§8).
%
%   filepath = saveMetrics(metrics, backbone)
%
%   Writes data/models/<backbone>_metrics.mat (paths().data.models) containing
%   the evaluation metrics produced by a REAL experiment run — e.g. the output
%   of evaluation/runValidation.m or classification/evaluateClassifier.m
%   (which in turn come from evaluation/metrics.m). Consumers load it via
%   core/loadMetrics.m.
%
%   Honesty (AGENTS.md guardrail #1): only genuine module output may be
%   stored. This function VALIDATES the metrics against the evaluation/metrics.m
%   contract (required fields + sane ranges) and raises otherwise — a
%   placeholder or hand-invented number is never written.
%
%   Failures (AGENTS.md raiseError convention):
%     RetinaSense:saveMetrics:MissingBackbone    backbone name empty
%     RetinaSense:saveMetrics:InvalidMetrics     not a metrics contract struct
%
%   Honest NaN: aucReferable may legitimately be NaN when a split has a single
%   class (degenerate AUROC, evaluation/metrics.m); it is accepted — never
%   substituted with a number.

    if nargin < 2 || isempty(backbone)
        raiseError('saveMetrics', 'MissingBackbone', ...
            'saveMetrics needs the backbone name to name the artifact.');
    end

    if ~isMetricsContract(metrics)
        raiseError('saveMetrics', 'InvalidMetrics', ...
            'Metrics struct is not a valid evaluation/metrics.m contract (missing/invalid fields); refusing to persist a placeholder.');
    end

    filepath = fullfile(paths().data.models, sprintf('%s_metrics.mat', backbone));
    save(filepath, 'metrics');
end

function tf = isMetricsContract(m)
%ISMETRICSCONTRACT  Validation of the evaluation/metrics.m output shape.
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
        tf = false; return;                 % no empty/zero-count "metrics"
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
    % aucReferable: finite in [0,1] OR the honest degenerate NaN.
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