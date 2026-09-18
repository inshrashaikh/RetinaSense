function explain = computeGradCAM(image, net, grading, evidence, params)
%COMPUTEGRADCAM  Stage 7: Grad-CAM attention map + lesion evidence overlay.
%
%   explain = computeGradCAM(image, net, grading, evidence, params)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.5):
%     explain.gradCam         HxWx1 double normalized attention heatmap
%     explain.attentionImage  HxWx3 uint8 overlay of attention on image
%     explain.evidenceOverlay HxWx3 uint8 lesion candidates + optic disc overlay (independent)
%     explain.note            string: model attention, NOT proof of causality
%
%   Real Grad-CAM path: with a trained net (SeriesNetwork/DAGNetwork/dlnetwork)
%   and a valid target layer (cfg.explainability.layers), computes the Grad-CAM
%   score map on the referable class via Deep Learning Toolbox gradCAM(). The
%   heatmap is resized to the working image and normalized 0..1.
%
%   Honest fallback (docs/ARCHITECTURE.md §9): if no net is supplied, or the
%   target layer is missing/invalid, or the toolbox call fails, this returns a
%   zero heatmap and a note — it NEVER fabricates attention.
%
%   Attention (Grad-CAM) and lesion evidence are kept separate and NEVER
%   conflated (§3.6). Grad-CAM is model attention, not causality.

    if nargin < 4; evidence = struct('lesions', struct()); end
    if nargin < 5; params = experiment_config().explainability; end

    note = params.note;   % 'Model attention - not proof of causality'
    [h, w, ~] = size(image);

    % ---- Grad-CAM (real path with trained net) ----
    gradCam = zeros(h, w, 'double');
    if ~isempty(net)
        try
            scoreMap = runGradCAM(net, image, grading, params);
            if ~isempty(scoreMap)
                gradCam = imresize(scoreMap, [h w]);
                gradCam = (gradCam - min(gradCam(:))) / ...
                    max(eps, max(gradCam(:)) - min(gradCam(:)));
                gradCam = double(gradCam);   % §4.5 contract: double heatmap
            end
        catch
            % Invalid layer / unsupported network: honest zero heatmap, note why.
            note = [note ' (Grad-CAM layer unavailable for this model; ' ...
                        'attention left empty rather than fabricating.)'];
        end
    end

    % ---- Attention image (jet colormap overlay on grayscale) ----
    attentionImage = im2uint8(zeros(h, w, 3));
    if any(gradCam(:) > 0)
        % Overlay jet heatmap on the grayscale working image (§7 colormap).
        base = repmat(im2uint8(rgb2gray(image)), [1 1 3]);
        cm = feval(params.colormap, 256);                 % jet(256), parula(256), ...
        camIdx = round(gradCam * (size(cm, 1) - 1)) + 1;  % 0..1 -> row
        heat = ind2rgb(camIdx, cm);
        attentionImage = im2uint8(0.55 * im2double(base) + 0.45 * heat);
    end

    % ---- Evidence overlay (independent of attention) ----
    % Maps lesion candidates + optic disc onto image. Only an actually
    % detected optic disc is drawn (honest empty: a not-detected disc leaves
    % the overlay as the plain image rather than stamping status text on it).
    evidenceOverlay = repmat(im2uint8(rgb2gray(image)), [1 1 3]);
    if isfield(evidence, 'lesions') && ~isempty(evidence.lesions)
        evidenceOverlay = overlayLesions(evidenceOverlay, evidence.lesions);
    end
    if isfield(evidence, 'opticDiscDetail') && isstruct(evidence.opticDiscDetail) ...
            && isfield(evidence.opticDiscDetail, 'center') ...
            && ~isempty(evidence.opticDiscDetail.center)
        try
            evidenceOverlay = overlayOpticDisc(evidenceOverlay, evidence.opticDiscDetail);
        catch
            % Optic disc overlay failed; keep evidence overlay as-is.
        end
    end

    explain = struct( ...
        'gradCam',         gradCam, ...
        'attentionImage',  attentionImage, ...
        'evidenceOverlay', evidenceOverlay, ...
        'note',            note);
end

function scoreMap = runGradCAM(net, image, grading, params)
%RUNGRADCAM  Invoke Deep Learning Toolbox gradCAM on the referable class.
    if isa(net, 'nnet.cnn.LayerGraph'); return; end            % not a trainable net
    if isa(net, 'DAGNetwork') || isa(net, 'SeriesNetwork')
        net = dlnetwork(net);
    elseif ~isa(net, 'dlnetwork')
        return;                                                % unsupported type
    end

    % Match the classifier input size at the config source (same resize and
    % normalization that classification/classifyImage.m applies for prediction),
    % so Grad-CAM and grading always use one consistent, config-driven input
    % pipeline per backbone.
    inputSize = experiment_config().classification.classify.inputSize(1:2);
    im = dlarray(single(imresize(image, inputSize)) / 255, 'SSCB');

    % Class index to explain: the graded class (referable decision class).
    label = grading.grade + 1;
    if ~isempty(params.layers) && isLayerValid(net, params.layers)
        scoreMap = gradCAM(net, im, label, params.layers);
    else
        scoreMap = gradCAM(net, im, label);
    end
    scoreMap = squeeze(extractdata(scoreMap));
end

function tf = isLayerValid(net, layerName)
%ISLAYERVALID  Best-effort check that layerName exists in the network. Failure
% returns false (-> Grad-CAM falls back to the default/no-layer path); the
% caller's try/catch keeps the module total even if the introspection errors.
    tf = false;
    try
        names = {};
        if isa(net, 'dlnetwork')
            L = net.Layers;
            if isa(L, 'nnet.cnn.layer.Layer') || isa(L, 'Layer')
                names = {L.Name};
            elseif isa(L, 'nnet.cnn.LayerGraph') || (isobject(L) && isprop(L, 'Name'))
                names = {L.Layers.Name};
            end
        elseif isprop(net, 'Layers')
            names = {net.Layers.Name};
        end
        tf = any(strcmp(layerName, names));
    catch
        tf = false;   % unknown introspect path: report layer as not found
    end
end

function ov = overlayLesions(base, lesions)
%OVERLAYLESIONS  Color-code candidate lesion maps onto the base overlay.
% Each lesion class draws in its own colour (advisory evidence only).
    colors = struct('exudates', [1 0.84 0], 'hemorrhages', [1 0 0], ...
                    'microaneurysms', [0 0.6 1], 'neoVasc', [0.6 0 1]);
    classes = fieldnames(lesions);
    for i = 1:numel(classes)
        les = lesions.(classes{i});
        if ~isstruct(les) || isempty(les.map) || ~any(les.map(:))
            continue;
        end
        if ~isfield(colors, classes{i}); continue; end
        m = imresize(les.map, [size(base,1) size(base,2)]);
        m = imdilate(m > 0, strel('disk', 2));   % visible on overlay
        c = colors.(classes{i});
        for ch = 1:3
            chMap = base(:, :, ch); chMap(m) = floor(c(ch) * 255); base(:, :, ch) = chMap;
        end
    end
    ov = im2uint8(base);
end
