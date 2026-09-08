function explain = computeGradCAM(image, net, grading, evidence, params)
%COMPUTEGRADCAM  Stage 7: Grad-CAM attention map + evidence overlay.
%
%   explain = computeGradCAM(image, net, grading, evidence, params)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.5):
%     explain.gradCam         HxWx1 double normalized attention heatmap
%     explain.attentionImage  HxWx3 uint8 overlay of attention on image
%     explain.evidenceOverlay HxWx3 uint8 lesion candidates overlay (independent)
%     explain.note            string: model attention, NOT proof of causality
%
%   Attention (Grad-CAM) and lesion evidence must never be conflated
%   (docs/ARCHITECTURE.md §3.6). Grad-CAM is Deep Learning Toolbox work.
%
%   TODO(Sprint 4+): gradCAM() on the trained net + imfuse colormap overlays.
%   Sprint 0 requires a trained net; without one it returns a neutral-black
%   heatmap and honest note — never fake attention.

    if nargin < 4; evidence = struct('lesions', struct()); end
    if nargin < 5; params = experiment_config().explainability; end

    note = params.note;   % 'Model attention - not proof of causality'

    [h, w, ~] = size(image);

    if isempty(net)
        gradCam = zeros(h, w, 'double');          % honest: no attention computed
        attentionImage = repmat(uint8(0), h, w);  % black overlay
        attentionImage = cat(3, attentionImage, attentionImage, attentionImage);
    else
        % TODO(Sprint 4+): real gradCAM(net, image, 'Layer', params.layers).
        gradCam = zeros(h, w, 'double');
        attentionImage = im2uint8(zeros(h, w, 3));
    end

    % Evidence overlay (independent of attention): maps lesions onto image.
    evidenceOverlay = im2uint8(zeros(h, w, 3));
    if isfield(evidence, 'lesions')
        im = im2uint8(rgb2gray(image));  % start from working image
        evidenceOverlay = repmat(im, [1 1 3]);
        classes = fieldnames(evidence.lesions);
        for i = 1:numel(classes)
            les = evidence.lesions.(classes{i});
            if isstruct(les) && ~isempty(les.map) && any(les.map(:))
                % TODO(Sprint 7): color-code candidates; once real detections exist.
            end
        end
    end

    explain = struct( ...
        'gradCam',         gradCam, ...
        'attentionImage',  attentionImage, ...
        'evidenceOverlay', evidenceOverlay, ...
        'note',            note);
end