function evalOut = evaluateClassifier(net, testDatastore)
%EVALUATECLASSIFIER  Honest hold-out evaluation of the DR classifier.
%
%   evalOut = evaluateClassifier(net, testDatastore)
%
%   net:            trained network (from trainClassifier / benchmark_backbones)
%   testDatastore:  imageDatastore with Labels = grade 0..4 (data.test from
%                   prepareClassifierData), or a 4-D image array + labels.
%
%   Returns a struct of REAL metrics computed against the hold-out labels
%   (docs/ARCHITECTURE.md §2 Stage 6 / §10):
%     evalOut.confusion     5x5 matrix
%     evalOut.accuracy      double
%     evalOut.referableSensitivity / referableSpecificity
%     evalOut.aucReferable  AUROC of referable (>=2) softmax decision
%     evalOut.perClassSensitivity / perClassSpecificity   1x5
%     evalOut.quadraticKappa
%     evalOut.n
%
%   Guardrail: no metric is fabricated. If no real net/labels are supplied,
%   this raises a clear error — it never invents numbers.
%
%   Messidor-2 (external) is NOT evaluated here; it is reserved for
%   evaluation/runValidation.m external fold only.

    cfg = experiment_config();
    if isempty(net)
        raiseError('evaluateClassifier', 'NoModel', ...
            'evaluateClassifier requires a trained net; none supplied.');
    end

    % ---- Collect labels + predictions on the hold-out set ----
    [labels, preds, probs] = predictOnTest(net, testDatastore, cfg);

    m = metrics(labels, preds, probs, 'confThreshold', cfg.referThreshold);

    % AUROC for referable (>=2) using the referable softmax probability.
    refProbAll = sum(probs(:, cfg.classification.referIndex:end), 2);
    refLab     = labels >= cfg.referThreshold;

    evalOut = struct( ...
        'confusion',              confusionmat(labels, preds), ...
        'accuracy',               m.accuracy, ...
        'referableSensitivity',   m.referableSensitivity, ...
        'referableSpecificity',   m.referableSpecificity, ...
        'aucReferable',           binaryAuc(refLab, refProbAll), ...
        'perClassSensitivity',    m.perClassSensitivity, ...
        'perClassSpecificity',    m.perClassSpecificity, ...
        'quadraticKappa',         m.quadraticKappa, ...
        'n',                      numel(labels));
end

function [labels, preds, probs] = predictOnTest(net, ds, cfg)
%PREDICTONTEST  Run inference and return Nx1 labels/preds, NxK probs.
    if isa(ds, 'matlab.io.datastore.ImageDatastore')
        predsC   = classify(net, ds);
        scores   = predict(net, ds);
        labels   = double(ds.Labels) - 1;        % categorical -> 0..4
        preds    = double(predsC) - 1;
        probs    = double(scores);
    else
        % Array + labels fallback: ds is a struct with .images (HxWx3xN) / .labels
        ims = single(ds.images) / 255;
        scores = predict(net, ims);
        probs  = double(scores);
        [~, preds] = max(probs, [], 2);
        preds  = preds - 1;
        labels = ds.labels(:);
    end
    probs = probs ./ sum(probs, 2);
end

function a = binaryAuc(lab, score)
%BINARYAUC  Area under the ROC curve for a binary label vs a continuous score.
    if numel(unique(lab)) < 2
        a = NaN;   % degenerate: single class present, AUROC undefined
        return;
    end
    [~, ord] = sort(score, 'descend');
    lab = lab(ord);
    pos = sum(lab == 1);
    neg = numel(lab) - pos;
    ranks = 1:numel(lab);
    a = (sum(ranks(lab == 1)) - pos*(pos+1)/2) / (pos * neg);
end
