function net = buildResNet50FromDump(dumpFile)
%BUILDRESNET50FROMDUMP  Reconstruct the trained ResNet-50 as a dlnetwork from a
%  scipy.io .mat dump of the PyTorch checkpoint (data/models/resnet50_dr_aptos.pt).
%
%  net = buildResNet50FromDump(dumpFile)
%
%  Artifact bridge used when the Deep Learning Toolbox ONNX/PyTorch importers are
%  absent: identical torchvision architecture plus the exact trained weights
%  (no retraining, no downloads). ImageNet normalization is applied via the
%  imageInputLayer zscore options (Mean/StandardDeviation), so the net consumes
%  [0,1]-scaled RGB exactly as classification/classifyImage.m feeds, matching the
%  exported ONNX graph (data/models/resnet50_dr_aptos.onnx) tensor-for-tensor.

    S = load(dumpFile);

    PLANES  = [64 128 256 512];
    BLOCKS  = [3  4   6   3];
    STRIDE0 = [1  2   2   2];

    % ---- stem ----
    in = imageInputLayer([224 224 3], 'Name', 'in', 'Normalization', 'zscore', ...
        'Mean', reshape([0.485 0.456 0.406], [1 1 3]), ...
        'StandardDeviation', reshape([0.229 0.224 0.225], [1 1 3]));
    conv1 = convolution2dLayer([7 7], 64, 'Stride', [2 2], 'Padding', [3 3 3 3], ...
        'Weights', permute(S.conv1_weight, [3 4 2 1]), 'Bias', reshape(S.conv1_bias(:), [1 1 64]), ...
        'Name', 'conv1');
    lgraph = layerGraph([...
        in; conv1; mkbn(S,'bn1',64,'bn1'); reluLayer('Name','relu1'); ...
        maxPooling2dLayer([3 3], 'Stride', [2 2], 'Padding', [1 1 1 1], 'Name', 'pool')]);

    prevOut = 'pool';
    for st = 1:numel(PLANES)
        C = PLANES(st);
        for bl = 1:BLOCKS(st)
            bname = sprintf('L%d_%d', st, bl-1);
            tag   = sprintf('layer%d_%d', st, bl-1);
            stride = STRIDE0(st);
            if bl > 1; stride = 1; end
            hasDs  = (bl == 1);

            convs = [ ...
                convolution2dLayer([1 1], C, 'Stride', 1, 'Padding', [0 0 0 0], ...
                    'Weights', permute(S.([tag '_conv1_weight']), [3 4 2 1]), 'Bias', zeros(1,1,C), ...
                    'Name', [bname '_conv1']); ...
                mkbn(S, [tag '_bn1'], C, [bname '_bn1']); reluLayer('Name',[bname '_relu1']); ...
                convolution2dLayer([3 3], C, 'Stride', stride, 'Padding', [1 1 1 1], ...
                    'Weights', permute(S.([tag '_conv2_weight']), [3 4 2 1]), 'Bias', zeros(1,1,C), ...
                    'Name', [bname '_conv2']); ...
                mkbn(S, [tag '_bn2'], C, [bname '_bn2']); reluLayer('Name',[bname '_relu2']); ...
                convolution2dLayer([1 1], 4*C, 'Stride', 1, 'Padding', [0 0 0 0], ...
                    'Weights', permute(S.([tag '_conv3_weight']), [3 4 2 1]), 'Bias', zeros(1,1,4*C), ...
                    'Name', [bname '_conv3']); ...
                mkbn(S, [tag '_bn3'], 4*C, [bname '_bn3'])];
            lgraph = addLayers(lgraph, convs);
            lgraph = connectLayers(lgraph, prevOut, [bname '_conv1']);

            if hasDs
                dsL = [ ...
                    convolution2dLayer([1 1], 4*C, 'Stride', stride, 'Padding', [0 0 0 0], ...
                        'Weights', permute(S.([tag '_downsample_0_weight']), [3 4 2 1]), 'Bias', zeros(1,1,4*C), ...
                        'Name', [bname '_ds']); ...
                    mkbn(S, [tag '_downsample_1'], 4*C, [bname '_dsbn'])];
                lgraph = addLayers(lgraph, dsL);
                lgraph = connectLayers(lgraph, prevOut, [bname '_ds']);
            end

            add = additionLayer(2, 'Name', [bname '_add']);
            relu3 = reluLayer('Name', [bname '_relu3']);
            lgraph = addLayers(lgraph, [add; relu3]);
            lgraph = connectLayers(lgraph, [bname '_bn3'], [bname '_add/in1']);
            if hasDs
                lgraph = connectLayers(lgraph, [bname '_dsbn'], [bname '_add/in2']);
            else
                lgraph = connectLayers(lgraph, prevOut, [bname '_add/in2']);
            end
            prevOut = [bname '_relu3'];
        end
    end

    % ---- head ----
    gap = globalAveragePooling2dLayer('Name', 'gap');
    fc = fullyConnectedLayer(5, 'Name', 'fc', ...
        'Weights', S.fc_weight, 'Bias', S.fc_bias(:));
    sm = softmaxLayer('Name', 'prob');
    lgraph = addLayers(lgraph, [gap; fc; sm]);
    lgraph = connectLayers(lgraph, prevOut, 'gap');
    net = dlnetwork(lgraph);
end

function bn = mkbn(S, tag, C, name)
    bn = batchNormalizationLayer('Name', name, ...
        'Scale', reshape(S.([tag '_weight']), [1 1 C]), ...
        'Offset', reshape(S.([tag '_bias']), [1 1 C]), ...
        'TrainedMean', reshape(S.([tag '_running_mean']), [1 1 C]), ...
        'TrainedVariance', reshape(S.([tag '_running_var']), [1 1 C]));
end