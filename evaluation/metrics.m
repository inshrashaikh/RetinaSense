function m = metrics(labels, preds, probs, varargin)
%METRICS  Honest classification metrics for RetinaSense evaluation.
%
%   m = metrics(labels, preds, probs)
%   m = metrics(labels, preds, probs, 'confThreshold', 2)
%
%   labels:  Nx1 integer ground-truth grades (0..4)
%   preds:   Nx1 integer predicted grades (0..4)
%   probs:   NxK soft probabilities (K=5), used for AUROC + ECE
%
%   Returns a struct with:
%     confusion              5x5 matrix (rows=label, cols=pred)
%     accuracy               double
%     perClassSensitivity    1x5
%     perClassSpecificity    1x5
%     referableSensitivity   binary >= confThreshold
%     referableSpecificity   binary >= confThreshold
%     aucReferable           binary AUROC of softmax(referable >= T)
%     quadraticKappa         quadratic weighted kappa over grades 0..4
%     ece                    expected calibration error (10 bins, argmax conf)
%     n                      number of samples
%
%   All pure math, no fabricated inputs. Trust inputs, report what comes out.

    p = inputParser;
    addParameter(p, 'confThreshold', 2);
    parse(p, varargin{:});
    T = p.Results.confThreshold;

    labels = labels(:); preds = preds(:);
    n = numel(labels);
    K = size(probs, 2);

    % Binary referable view (grade >= T).
    refLab = labels >= T;
    refPred = preds >= T;

    acc = mean(preds == labels);
    cm  = confusionmat(labels, preds);

    perSe = zeros(1, K); perSp = zeros(1, K);
    for g = 0:K-1
        perSe(g+1) = sens(preds == g, labels == g);
        perSp(g+1) = spec(preds == g, labels == g);
    end

    % Referable AUROC from the softmax probability of any referable grade.
    if n >= 2 && size(probs, 2) >= T+1
        refProb = sum(probs(:, T+1:end), 2);
        aucRef  = binaryAuc(refLab, refProb);
    else
        aucRef = NaN;
    end

    m = struct( ...
        'confusion',              cm, ...
        'accuracy',               acc, ...
        'perClassSensitivity',    perSe, ...
        'perClassSpecificity',    perSp, ...
        'referableSensitivity',   sens(refPred, refLab), ...
        'referableSpecificity',   spec(refPred, refLab), ...
        'aucReferable',           aucRef, ...
        'quadraticKappa',         qwk(labels, preds), ...
        'ece',                    ece(probs, labels), ...
        'n',                      n);
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

function a = binaryAuc(lab, score)
%BINARYAUC  Area under the ROC curve for binary labels vs a continuous score.
% Requires both classes present; otherwise AUROC is undefined -> NaN.
% rank 1 = LOWEST score, so higher-scoring positives contribute high ranks:
% AUC = P(score(pos) > score(neg)), equal to 1 for perfect positive-high
% separation (Mann-Whitney U / n_pos / n_neg).
    if numel(unique(lab)) < 2
        a = NaN;
        return;
    end
    pos = sum(lab == 1); neg = numel(lab) - pos;
    if pos == 0 || neg == 0
        a = NaN; return;
    end
    [~, ord] = sort(score, 'ascend');          % rank 1 = lowest score
    lab = lab(ord);
    ranks = 1:numel(lab);
    a = (sum(ranks(lab == 1)) - pos*(pos+1)/2) / (pos * neg);
end