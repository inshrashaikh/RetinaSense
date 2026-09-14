function probs = predictDatastore(net, ds, cfg)
%PREDICTDATASTORE  Batch softmax probabilities from a trained net over a datastore.
%
%   probs = predictDatastore(net, ds, cfg)
%
%   net:  trained network (dlnetwork / SeriesNetwork / DAGNetwork)
%   ds:   imageDatastore with Labels = grade 0..4 (data.test etc.)
%   cfg:  experiment_config()
%
%   Returns N x numClasses softmax probabilities (row-normalized to sum 1).
%
%   DAG/Series networks accept imageDatastore input via predict/classify.
%   A dlnetwork does not; it must be fed resized numeric batches at the net
%   input size (classification_config.classify.inputSize), with batch size from
%   classification_config.train.miniBatchSize. This helper honors both so the
%   evaluation workflow (evaluation/runValidation.m, classification/evaluateClassifier.m)
%   accepts any supported net type.

    if ~isa(net, 'dlnetwork')
        scores = predict(net, ds);
        probs  = double(scores);
    else
        inputSize = cfg.classification.classify.inputSize(1:2);
        batchSize = cfg.classification.train.miniBatchSize;
        files = ds.Files;
        n = numel(files);
        probs = zeros(n, cfg.classification.numClasses);
        for i = 1:batchSize:n
            idx = i:min(n, i+batchSize-1);
            ims = zeros([inputSize 3 numel(idx)], 'single');
            for k = 1:numel(idx)
                im = imread(files{idx(k)});
                im = imresize(im, inputSize);
                ims(:, :, :, k) = single(im) / 255;
            end
            sc = predict(net, ims);
            probs(idx, :) = double(sc);
        end
    end
    probs = probs ./ sum(probs, 2);
end