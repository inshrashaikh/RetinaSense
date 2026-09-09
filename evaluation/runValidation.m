function results = runValidation(net, calibT)
%RUNVALIDATION  Hold-out validation of the DR pipeline (+ external Messidor-2).
%
%   results = runValidation(net, calibT)
%
%   net:      trained network (ClassifierNet / dlnetwork from trainClassifier)
%   calibT:   temperature T fitted by fitTemperature on the VALIDATION split
%             (pass [] to skip calibrated ECE reporting).
%
%   Computes (via evaluation/metrics.m) on the hold-out TEST split:
%     confusion matrix, accuracy, per-class SE/SP, referable SE/SP + AUROC,
%     quadratic kappa, and ECE (uncalibrated and, if calibT given, calibrated).
%
%   EXTERNAL fold: rows in the manifest with split='external' (Messidor-2) are
%   evaluated separately and reported under results.external. Messidor-2 is
%   never used for training or temperature fitting (docs/ARCHITECTURE.md §8).
%
%   HONESTY (AGENTS.md): requires a real trained net; raises otherwise. No
%   fabricated numbers are ever reported here.

    cfg = experiment_config();
    data = prepareClassifierData();

    if isempty(net) || isempty(data.test)
        raiseError('runValidation', 'NoModelOrData', ...
            'runValidation needs a trained net and real test split.');
    end

    % ---- Hold-out test evaluation ----
    [lab, pred, probs, refProb] = predictOn(testNet(net), data.test, cfg);

    m = metrics(lab, pred, probs, 'confThreshold', cfg.referThreshold);

    % Calibrated ECE (only if a temperature was actually fitted).
    calEce = NaN; calConf = [];
    if ~isempty(calibT) && isfinite(calibT) && calibT > 0
        calProbs = temperatureProbs(probs, calibT);
        calEce   = eceOnly(calProbs, lab);
        calConf  = max(calProbs, [], 2);
    end

    results = struct( ...
        'n',                m.n, ...
        'confusion',        m.confusion, ...
        'accuracy',         m.accuracy, ...
        'referableSensitivity', m.referableSensitivity, ...
        'referableSpecificity', m.referableSpecificity, ...
        'aucReferable',     m.aucReferable, ...
        'perClassSensitivity', m.perClassSensitivity, ...
        'perClassSpecificity', m.perClassSpecificity, ...
        'quadraticKappa',   m.quadraticKappa, ...
        'ece',              m.ece, ...
        'calibratedEce',    calEce, ...
        'calibratedConf',   calConf, ...
        'temperature',      calibT, ...
        'external',         validateExternal(net, data.external, cfg));
end

function ext = validateExternal(net, extDs, cfg)
%VALIDATEEXTERNAL  Messidor-2 external fold (never used for train/calib).
    if isempty(extDs); ext = struct('n', 0, 'note', 'no external split in manifest'); return; end

    [lab, pred, probs, ~] = predictOn(testNet(net), extDs, cfg);
    m = metrics(lab, pred, probs, 'confThreshold', cfg.referThreshold);

    ext = struct( ...
        'n', m.n, ...
        'confusion', m.confusion, ...
        'referableSensitivity', m.referableSensitivity, ...
        'referableSpecificity', m.referableSpecificity, ...
        'aucReferable', m.aucReferable, ...
        'quadraticKappa', m.quadraticKappa, ...
        'note', 'Messidor-2 external validation — never used in training or calibration.');
end

% ---- helpers ----
function n = testNet(net)
    if ~isa(net, 'dlnetwork') && ~isa(net, 'DAGNetwork') && ~isa(net, 'SeriesNetwork')
        raiseError('runValidation', 'BadNet', 'Unsupported network type.');
    end
    n = net;
end

function [lab, pred, probs, refProb] = predictOn(net, ds, cfg)
    scores = predict(net, ds);
    scores = double(scores);
    probs  = scores ./ sum(scores, 2);
    [~, pred] = max(probs, [], 2);
    lab   = double(ds.Labels) - 1;
    pred  = pred - 1;
    refProb = sum(probs(:, cfg.classification.referIndex:end), 2);
end

function cp = temperatureProbs(probs, T)
    z = log(max(probs, eps)) ./ T;          % invert softmax, rescale, re-softmax
    z = z - max(z, [], 2);
    cp = exp(z) ./ sum(exp(z), 2);
end

function e = eceOnly(probs, labels)
    % ECE from (probabilities, labels) only — no prediction dependency.
    probs = probs;
    [conf, pred] = max(probs, [], 2);
    pred = pred - 1;
    n = numel(labels);
    if n == 0; e = 0; return; end
    B = 10;
    bins = discretize(conf, 0:1/B:1);
    e = 0;
    for b = 1:B
        idx = find(bins == b);
        if isempty(idx); continue; end
        accB = mean(pred(idx) == labels(idx));
        e = e + (numel(idx)/n) * abs(accB - mean(conf(idx)));
    end
end