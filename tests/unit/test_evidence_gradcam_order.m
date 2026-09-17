function tests = test_evidence_gradcam_order
%TEST_EVIDENCE_GRADCAM_ORDER  Focused tests for evidence + Grad-CAM integration.
%
%   Verifies (docs/ARCHITECTURE.md §3.6 / §4.5):
%     1. analysis/analyzeRetina runs before explainability/computeGradCAM in
%        scripts/runPipeline.m, and c.evidence is passed into computeGradCAM.
%     2. In real-model mode the loaded net reaches computeGradCAM.
%     3. Grad-CAM (model attention) and retinal evidence (independent,
%        advisory) stay separate; evidence never modifies grading/referral.
%     4. Mock / unavailable-data paths keep the honest zero / empty fallback.
%     5. computeGradCAM outputs satisfy the §4.5 contract.
%     6. The note states attention is not proof of causality.
%
%   Run:  results = runtests('tests/unit/test_evidence_gradcam_order')
%
%   The real-net test needs the Deep Learning Toolbox; other tests run
%   everywhere.

    tests = functiontests(localfunctions);
end

% =====================================================================
%  Ordering & plumbing in runPipeline
% =====================================================================

function testExplainabilityRunsAfterAnalysis(testCase)
% Stage order must be analysis -> grading -> explainability, so evidence
% exists before Grad-CAM needs it.
    c = runPipeline('scenario', 'good', 'mock', true);
    ix = @(s) find(strcmp(c.pipeline.stages, s));
    verifyFalse(testCase, isempty(ix('analysis')));
    verifyTrue(testCase, ix('analysis') < ix('grading'));
    verifyTrue(testCase, ix('grading') < ix('explainability'));
end

function testPipelineEvidenceReachesGradCAM(testCase)
% The case carries evidence and the explainability output exposes the
% independent evidence overlay (h x w x 3 uint8) sized to the image.
    c = runPipeline('scenario', 'good', 'mock', true);
    verifyTrue(testCase, isfield(c.evidence, 'lesions'));
    verifyTrue(testCase, isfield(c.evidence, 'opticDiscDetail'));
    verifyEqual(testCase, size(c.explain.evidenceOverlay), ...
        [size(c.image,1) size(c.image,2) 3]);
    verifyEqual(testCase, class(c.explain.evidenceOverlay), 'uint8');
end

% =====================================================================
%  Evidence reaches computeGradCAM (module-level, deterministic)
% =====================================================================

function testEvidenceLesionsReachOverlay(testCase)
% A lesion map in evidence MUST change the evidence overlay, proving the
% independent evidence truly flows into Grad-CAM's output (advisory only).
    img = uint8(110 * ones(64, 64, 3));
    grading = struct('rawProbs',[0.9 0.05 0.03 0.01 0.01],'grade',0, ...
        'referableProb',0.05,'referable',false,'modelFile','');
    evidence = emptyEvidence(64, 64);
    evidence.lesions.exudates.map(20:25, 20:25) = true;

    explain = computeGradCAM(img, [], grading, evidence, ...
        experiment_config().explainability);

    base = repmat(im2uint8(rgb2gray(img)), [1 1 3]);
    verifyFalse(testCase, isequal(explain.evidenceOverlay, base), ...
        'Lesion evidence must be visible in the evidence overlay');
    verifyTrue(testCase, any(explain.evidenceOverlay(:) ~= base(:)));
end

function testEmptyEvidenceHonestOverlay(testCase)
% No lesion evidence -> the overlay is exactly the plain grayscale image
% (honest empty; nothing invented).
    img = uint8(110 * ones(64, 64, 3));
    grading = struct('rawProbs',[0.9 0.05 0.03 0.01 0.01],'grade',0, ...
        'referableProb',0.05,'referable',false,'modelFile','');
    explain = computeGradCAM(img, [], grading, emptyEvidence(64, 64), ...
        experiment_config().explainability);
    base = repmat(im2uint8(rgb2gray(img)), [1 1 3]);
    verifyEqual(testCase, explain.evidenceOverlay, base);
end

% =====================================================================
%  Evidence never modifies grading / referral
% =====================================================================

function testEvidenceDoesNotChangeGrading(testCase)
% Whatever evidence the pipeline produces, the DR grade/referral depend only
% on image + net: the pipeline grading equals a standalone image-only
% classification.
    c = runPipeline('scenario', 'good', 'mock', true);
    standalone = classifyImage(c.image, [], experiment_config().classification);
    verifyEqual(testCase, c.grading.rawProbs, standalone.rawProbs, 'AbsTol', 1e-12);
    verifyEqual(testCase, c.grading.grade, standalone.grade);
    verifyEqual(testCase, c.grading.referableProb, standalone.referableProb, 'AbsTol', 1e-12);
    verifyEqual(testCase, c.grading.referable, standalone.referable);
end

function testGradCAMDoesNotMutateGrading(testCase)
% Calling Grad-CAM with varied evidence leaves the grading struct untouched.
    img = uint8(110 * ones(64, 64, 3));
    grading = struct('rawProbs',[0.9 0.05 0.03 0.01 0.01],'grade',0, ...
        'referableProb',0.05,'referable',false,'modelFile','');
    snap = grading;
    rich = emptyEvidence(64, 64);
    rich.lesions.hemorrhages.map(30:35, 30:35) = true;
    computeGradCAM(img, [], grading, rich, experiment_config().explainability);
    computeGradCAM(img, [], grading, emptyEvidence(64, 64), ...
        experiment_config().explainability);
    verifyEqual(testCase, grading.rawProbs, snap.rawProbs);
    verifyEqual(testCase, grading.grade, snap.grade);
    verifyEqual(testCase, grading.referable, snap.referable);
end

% =====================================================================
%  Contract validation (§4.5) — honest fallback
% =====================================================================

function testGradCAMContractMockFallback(testCase)
% No net: gradCam is an all-zero h x w double map; attentionImage all-zero
% uint8; evidence overlay valid. Honest fallback, nothing fabricated.
    img = uint8(110 * ones(64, 64, 3));
    grading = struct('rawProbs',[0.9 0.05 0.03 0.01 0.01],'grade',0, ...
        'referableProb',0.05,'referable',false,'modelFile','');
    explain = computeGradCAM(img, [], grading, emptyEvidence(64, 64), ...
        experiment_config().explainability);
    verifyEqual(testCase, size(explain.gradCam), [64 64]);
    verifyEqual(testCase, class(explain.gradCam), 'double');
    verifyTrue(testCase, all(explain.gradCam(:) == 0));
    verifyEqual(testCase, size(explain.attentionImage), [64 64 3]);
    verifyEqual(testCase, class(explain.attentionImage), 'uint8');
    verifyTrue(testCase, all(explain.attentionImage(:) == 0));
    verifyEqual(testCase, size(explain.evidenceOverlay), [64 64 3]);
    verifyEqual(testCase, class(explain.evidenceOverlay), 'uint8');
    verifyTrue(testCase, ischar(explain.note) && ~isempty(explain.note));
end

function testMockPipelineFallbackHonest(testCase)
% End-to-end mock: zero attention map + attention note, valid overlay.
    c = runPipeline('scenario', 'good', 'mock', true);
    verifyEqual(testCase, c.grading.modelFile, '');
    verifyTrue(testCase, all(c.explain.gradCam(:) == 0));
    verifyTrue(testCase, all(c.explain.attentionImage(:) == 0));
    verifyEqual(testCase, size(c.explain.evidenceOverlay), ...
        [size(c.image,1) size(c.image,2) 3]);
end

% =====================================================================
%  Grad-CAM note: attention, not causality
% =====================================================================

function testGradCamNoteNotCausality(testCase)
    c = runPipeline('scenario', 'good', 'mock', true);
    note = lower(c.explain.note);
    verifyTrue(testCase, contains(note, 'model attention'));
    verifyTrue(testCase, contains(note, 'not proof of causality'));
end

% =====================================================================
%  Real net reaches Grad-CAM (requires Deep Learning Toolbox)
% =====================================================================

function testRealNetReachesGradCAM(testCase)
% In real-model mode the loaded net flows into computeGradCAM: the attention
% map targets the graded class and the honest ''layer unavailable'' fallback
% note is NOT appended (a passed-but-incompatible net would be).
    if ~isToolboxAvailable()
        warning('test_evidence_gradcam_order:skip', ...
            'Deep Learning Toolbox unavailable; skipping real-net Grad-CAM test.');
        return;
    end
    net = makeTestNet();
    netArt = writeArtifact('evgc_test', net);
    calArt = fullfile(paths().data.models, 'evgc_test_calib.mat');
    saveCalibration(1.0, 'evgc_test');
    bench  = writeBenchmarkRecord('evgc_test');
    cleanup = onCleanup(@() restoreAll(netArt, calArt, bench));

    c = runPipeline('scenario', 'good', 'mock', false);
    verifyEqual(testCase, size(c.explain.gradCam), [size(c.image,1) size(c.image,2)]);
    verifyEqual(testCase, class(c.explain.gradCam), 'double');
    verifyEqual(testCase, size(c.explain.attentionImage), ...
        [size(c.image,1) size(c.image,2) 3]);
    verifyEqual(testCase, size(c.explain.evidenceOverlay), ...
        [size(c.image,1) size(c.image,2) 3]);
    verifyFalse(testCase, contains(lower(c.explain.note), 'layer unavailable'), ...
        'Grad-CAM must not report a fallback when a real net is supplied');
    verifyTrue(testCase, contains(lower(c.explain.note), 'model attention'));
end

% =====================================================================
%  Helpers
% =====================================================================

function evidence = emptyEvidence(h, w)
%EMPTYEVIDENCE  Minimal valid §5 evidence struct with no detections.
    les = struct('exudates',struct('map',false(h,w),'count',0,'features',zeros(4,0)), ...
                 'hemorrhages',struct('map',false(h,w),'count',0,'features',zeros(4,0)), ...
                 'microaneurysms',struct('map',false(h,w),'count',0,'features',zeros(4,0)), ...
                 'neoVasc',struct('map',false(h,w),'count',0,'features',zeros(4,0)));
    evidence = struct('vesselMask', false(h, w), 'opticDisc', [], 'fovea', [], ...
        'lesions', les, 'confidence', 'low', ...
        'opticDiscDetail', struct('center', [], 'bbox', [], 'confidence', 0, ...
            'status', 'not_detected', 'method', '', 'note', ''));
end

function net = makeTestNet()
%MAKETESTNET  Minimal UNTRAINED dlnetwork (random init); plumbing only.
    layers = [ ...
        imageInputLayer([224 224 3], 'Name', 'input'), ...
        convolution2dLayer(3, 4, 'Padding', 'same', 'Name', 'conv1'), ...
        reluLayer('Name', 'relu1'), ...
        fullyConnectedLayer(5, 'Name', 'fc'), ...
        softmaxLayer('Name', 'softmax')];
    net = dlnetwork(layerGraph(layers));
end

function artFile = writeArtifact(backbone, net)
    artFile = fullfile(paths().data.models, sprintf('%s_dr_aptos.mat', backbone));
    save(artFile, 'net', 'backbone');
end

function b = writeBenchmarkRecord(backbone)
    b.file = fullfile(paths().data.models, 'backbone_benchmark.json');
    b.present = exist(b.file, 'file') == 2;
    b.text = '';
    if b.present; b.text = fileread(b.file); end
    rec = struct('chosenBackbone', backbone, 'targetsMet', true);
    fid = fopen(b.file, 'w');
    fwrite(fid, jsonencode(rec)); fclose(fid);
end

function restoreAll(netArt, calArt, b)
    deleteIfExists(netArt);
    deleteIfExists(calArt);
    if b.present
        fid = fopen(b.file, 'w');
        fwrite(fid, b.text); fclose(fid);
    else
        deleteIfExists(b.file);
    end
end

function tf = isToolboxAvailable()
    tf = ~isempty(which('dlnetwork')) && ~isempty(which('gradCAM')) && ...
         ~isempty(which('trainNetwork'));
end

function deleteIfExists(f)
    if exist(f, 'file'); delete(f); end
end