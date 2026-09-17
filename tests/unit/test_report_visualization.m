function tests = test_report_visualization
%TEST_REPORT_VISUALIZATION  Visualization honesty + real image embedding in
%   reporting/buildReport.m and reporting/renderReport.m.
%
%   Guards against the over-claim bug: a nonempty-but-black attention image
%   (zero-map mock) must NEVER be advertised as available (AGENTS.md #3), and
%   the PDF page 2 must embed the REAL working/attention/evidence images when
%   they contain actual content.

    tests = functiontests(localfunctions);
end

% =====================================================================
%  Honest availability (zero-map mock must not over-claim)
% =====================================================================

function test_mockNeverOverClaimsAttention(testCase)
%TEST_MOCKNEVEROVERCLAIMSATTENTION  Zero-map mock -> no Grad-CAM / attention
%   panels are advertised, even though computeGradCAM returns nonempty black
%   arrays. Evidence overlay availability must instead match the evidence the
%   analysis module actually produced (the mock may legitimately localize the
%   optic disc on the synthetic image).
    c = runPipeline('scenario', 'good', 'mock', true);
    testCase.verifyTrue(~isempty(c.explain.attentionImage), ...
        'computeGradCAM mock returns a nonempty (black) attention array');
    testCase.verifyFalse(any(c.explain.gradCam(:) > 0), ...
        'mock Grad-CAM must be the honest zero map');

    r = buildReport(c, experiment_config());
    testCase.verifyFalse(r.data.explainability.gradCamAvailable, ...
        'zero heatmap must not be advertised as Grad-CAM available');
    testCase.verifyFalse(r.data.explainability.attentionImageAvailable, ...
        'black/zero-map attention image must NOT be advertised (over-claim bug)');

    % Overlay availability must be consistent with actual evidence content.
    expectedOverlay = evidenceHasContent(c.evidence);
    testCase.verifyEqual(...
        r.data.explainability.evidenceOverlayAvailable, expectedOverlay, ...
        'evidence overlay availability must match evidence content');
    if expectedOverlay
        testCase.verifyTrue(~isempty(r.images.evidenceOverlay), ...
            'contentful evidence must be carried for rendering');
    else
        testCase.verifyTrue(isempty(r.images.evidenceOverlay));
    end

    % Images live in report.images (renderer), never in report.data.
    testCase.verifyTrue(isfield(r.images, 'image') && ~isempty(r.images.image));
    testCase.verifyTrue(isempty(r.images.attentionImage), ...
        'zero-map attention image must not be carried for rendering');
    testCase.verifyFalse(isfield(r.data, 'image'), ...
        'images must stay out of the machine-readable data subset');
end

function test_originalAlwaysEmbeddedInPdf(testCase)
%TEST_ORIGINALALWAYSEMBEDDEDINPDF  PDF renders with the original image panel
%   even when no AI attention exists (honest "Not available" placeholders).
    c = runPipeline('scenario', 'good', 'mock', true);
    r = buildReport(c, experiment_config());
    out = fullfile(tempdir, 'rs_vis_pdf');
    if ~exist(out, 'dir'); mkdir(out); end
    testCase.addTeardown(@removeDirRecursive, out);
    fp = renderReport(r, struct('out', out));
    testCase.verifyTrue(exist(fp, 'file') == 2, 'no PDF produced');
end

% =====================================================================
%  Real content -> flags true, images embedded, PDF renders
% =====================================================================

function test_realContentEmbedsAndRenders(testCase)
%TEST_REALCONTENTEMBEDSANDRENDERS  Genuine, non-trivial attention + evidence
%   content is carried into the report and rendered into the PDF.
    c = runPipeline('scenario', 'good', 'mock', true);
    h = size(c.image, 1); w = size(c.image, 2);

    % Real-looking (non-trivial) attention: smooth ramp heatmap + overlay.
    ramp = reshape(linspace(0, 1, h*w), h, w);
    c.explain.gradCam = ramp;
    c.explain.attentionImage = im2uint8(repmat(ramp, [1 1 3]) * 255);

    % Real lesion evidence: candidate exudates present -> overlay has content.
    c.evidence.lesions.exudates.count = 3;
    c.explain.evidenceOverlay = c.image;

    r = buildReport(c, experiment_config());
    testCase.verifyTrue(r.data.explainability.gradCamAvailable);
    testCase.verifyTrue(r.data.explainability.attentionImageAvailable);
    testCase.verifyTrue(r.data.explainability.evidenceOverlayAvailable);
    testCase.verifyTrue(any(r.images.attentionImage(:) > 0), ...
        'attention image must be carried when available');
    testCase.verifyTrue(~isempty(r.images.evidenceOverlay));

    out = fullfile(tempdir, 'rs_vis_pdf2');
    if ~exist(out, 'dir'); mkdir(out); end
    testCase.addTeardown(@removeDirRecursive, out);
    fp = renderReport(r, struct('out', out));
    testCase.verifyTrue(exist(fp, 'file') == 2, 'no PDF produced with visuals');

    % Non-trivial heatmap must also survive as the stored raw map.
    testCase.verifyTrue(any(r.images.gradCam(:) > 0));
end

function removeDirRecursive(d)
    if exist(d, 'dir'); rmdir(d, 's'); end
end

function tf = evidenceHasContent(evidence)
%EVIDENCEHASCONTENT  Mirrors buildReport.evidenceOverlayHasContent: true when
%   any lesion class has candidates or the optic disc was localized.
    tf = false;
    if isfield(evidence, 'opticDiscDetail') && isstruct(evidence.opticDiscDetail) && ...
            ~isempty(evidence.opticDiscDetail.center)
        tf = true;
        return;
    end
    if isfield(evidence, 'lesions') && isstruct(evidence.lesions)
        for f = fieldnames(evidence.lesions)'
            if isstruct(evidence.lesions.(f{1})) && ...
                    isfield(evidence.lesions.(f{1}), 'count') && ...
                    evidence.lesions.(f{1}).count > 0
                tf = true;
                return;
            end
        end
    end
end