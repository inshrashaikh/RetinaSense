function m = metrics(labels, preds, probs, varargin)
%METRICS  Honest classification metrics for RetinaSense evaluation.
%
%   m = metrics(labels, preds, probs)
%   m = metrics(labels, preds, probs, 'confThreshold', 2)
%
%   labels:  Nx1 integer ground-truth grades (0..4)
%   preds:   Nx1 integer predicted grades (0..4)
%   probs:   NxK soft probabilities (K=5), graded thresholds for ECE
%
%   Returns struct with accuracy, per-class sensitivity/specificity, referable
%   (>=confThreshold) SE/SP, quadratic weighted kappa, and expected calibration
%   error (ECE) — the core metrics friends use from Sprint 8 onward. All pure
%   math, no fabricated inputs. Trust inputs, report what comes out.
%
%   TODO(Sprint 8): wire into runValidation.m + runAblation.m.

    p = inputParser;
    addParameter(p, 'confThreshold', 2);
    parse(p, varargin{:});
    T = p.Results.confThreshold;

    labels = labels(:); preds = preds(:);
    n = numel(labels);

    % Binary referable view (grade >= T).
    refLab = labels >= T;
    refPred = preds >= T;

    acc = mean(preds == labels);

    m = struct( ...
        'accuracy', acc, ...
        'referableSensitivity', sens(refPred, refLab), ...
        'referableSpecificity', spec(refPred, refLab), ...
        'quadraticKappa', qwk(labels, preds), ...
        'ece', ece(probs, labels));
end

function v = sens(pred, lab)
    v = sum(pred & lab) / max(1, sum(lab));
end

function v = spec(pred, lab)
    tn = sum(~pred & ~lab);
    fp = sum(pred & ~lab);
    v = tn / max(1, tn + fp);
end

function k = qwk(lab, pred)
    % Quadratic weighted kappa over grades 0..4.
    w = abs((0:4)' - (0:4)) .^ 2;
    N = histcounts(lab, -0.5:1:4.5)' * histcounts(pred, -0.5:1:4.5);
    obs = histcounts2(lab, pred, -0.5:1:4.5, -0.5:1:4.5);
    k = 1 - sum(w .* obs) / max(1e-12, sum(w .* N));
end

function e = ece(probs, labels)
    % Expected calibration error with 10 bins, argmax confidence.
    probs = probs;            % N x K
    [conf, pred] = max(probs, [], 2);
    pred = pred - 1;          % 0..4
    n = numel(labels);
    if n == 0; e = 0; return; end
    B = 10;
    bins = discretize(conf, 0:1/B:1);   % edges [0, .1, ..., 1]
    e = 0; cnt = 0;
    for b = 1:B
        idx = find(bins == b);
        if isempty(idx); continue; end
        accB = mean(pred(idx) == labels(idx));
        e = e + (numel(idx) / n) * abs(accB - mean(conf(idx)));
    end
end