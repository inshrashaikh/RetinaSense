function tests = test_load_trained_model
%TEST_LOAD_TRAINED_MODEL  Focused tests for real-artifact consumption.
%
%   P0 backend wiring (docs/ARCHITECTURE.md §8): scripts/runPipeline.m must
%   load data/models/<backbone>_dr_aptos.mat (via core/loadTrainedModel.m) and
%   hand the loaded net to classification/classifyImage.m and
%   explainability/computeGradCAM.m whenever cfg.model.available is true,
%   while keeping net=[] for the honest mock path.
%
%   Run:  results = runtests('tests/unit/test_load_trained_model')
%
%   Real-network tests need the Deep Learning Toolbox; without it they are
%   skipped with a warning (no fabricated load). The mock and error-path
%   tests run everywhere.

    tests = functiontests(localfunctions);
end

% =====================================================================
%  Mock path (no DL toolbox required)
% =====================================================================

function test_mockPathStillWorks(testCase)
% Explicit mock runPipeline('mock', true) must keep the honest mock:
% modelFile='', zero Grad-CAM map, safety note intact.
    c = runPipeline('scenario', 'good', 'mock', true);
    verifyEqual(testCase, c.grading.modelFile, '');
    verifyTrue(testCase, all(c.explain.gradCam(:) == 0));
    verifyTrue(testCase, contains(lower(c.explain.note), 'attention'));
end

function test_mockDisabledWithoutModelStillErrors(testCase)
% The existing MissingModel gate (mock=false, no benchmark record) is
% preserved by the P0 wiring.
    if experiment_config().model.available
        warning('test_load_trained_model:skip', ...
            'Benchmark-recorded model present; skipping MissingModel gate test.');
        return;
    end
    verifyError(testCase, @() runPipeline('scenario', 'good', 'mock', false), ...
        'RetinaSense:runPipeline:MissingModel');
end

% =====================================================================
%  Loader error paths (no DL toolbox required)
% =====================================================================

function test_missingArtifactRaises(testCase)
    cfg = struct('model', struct('backbone', 'no_such_backbone', 'available', true));
    verifyError(testCase, @() loadTrainedModel(cfg), ...
        'RetinaSense:loadTrainedModel:MissingArtifact');
end

function test_missingBackboneRaises(testCase)
    cfg = struct('model', struct('backbone', '', 'available', true));
    verifyError(testCase, @() loadTrainedModel(cfg), ...
        'RetinaSense:loadTrainedModel:MissingModel');
end

function test_invalidArtifactRaises(testCase)
% A present .mat without a usable net must fail loudly, never fabricate.
    artFile = fullfile(paths().data.models, 'invalid_test_dr_aptos.mat');
    cleanup = onCleanup(@() deleteIfExists(artFile));
    foo = 1;                % not a network
    save(artFile, 'foo');
    cfg = struct('model', struct('backbone', 'invalid_test', 'available', true));
    verifyError(testCase, @() loadTrainedModel(cfg), ...
        'RetinaSense:loadTrainedModel:InvalidArtifact');
end

% =====================================================================
%  Real artifact path (requires Deep Learning Toolbox)
% =====================================================================

function test_realArtifactLoadingPath(testCase)
% loadTrainedModel returns the net stored in data/models/<backbone>_dr_aptos.mat.
    if ~isToolboxAvailable()
        warning('test_load_trained_model:skip', ...
            'Deep Learning Toolbox unavailable; skipping real loading path test.');
        return;
    end
    net = makeTestNet();
    artFile = writeArtifact('loader_path_test', net);
    cleanup  = onCleanup(@() deleteIfExists(artFile));
    cfg = struct('model', struct('backbone', 'loader_path_test', 'available', true));
    loaded = loadTrainedModel(cfg);
    verifyTrue(testCase, isa(loaded, 'dlnetwork'), 'Loaded artifact must be a network object');
end

function test_loadedNetReachesClassificationAndGradCAM(testCase)
% End-to-end through runPipeline: with a benchmark-recorded backbone the
% loaded net must reach classifyImage (real path, non-empty modelFile) and
% computeGradCAM (attention attempted for the graded class; the honest
% ''unavailable'' fallback note must NOT appear).
    if ~isToolboxAvailable()
        warning('test_load_trained_model:skip', ...
            'Deep Learning Toolbox unavailable; skipping net-reaches-modules test.');
        return;
    end
    net = makeTestNet();
    artFile = writeArtifact('reach_modules_test', net);
    calArt  = fullfile(paths().data.models, 'reach_modules_test_calib.mat');
    saveCalibration(1.0, 'reach_modules_test');
    bench   = writeBenchmarkRecord('reach_modules_test');
    cleanup  = onCleanup(@() restoreAll(artFile, calArt, bench));

    c = runPipeline('scenario', 'good', 'mock', false);
    verifyTrue(testCase, ~isempty(c.grading.modelFile), ...
        'Real-path grading must identify the model');
    verifyEqual(testCase, numel(c.grading.rawProbs), 5);
    verifyEqual(testCase, sum(c.grading.rawProbs), 1, 'AbsTol', 1e-9);
    verifyEqual(testCase, size(c.explain.gradCam), [size(c.image,1) size(c.image,2)]);
    verifyFalse(testCase, contains(lower(c.explain.note), 'layer unavailable'), ...
        'Grad-CAM must not silently fall back when a real net is supplied');
end

% =====================================================================
%  Helpers
% =====================================================================

function net = makeTestNet()
%MAKETESTNET  Minimal UNTRAINED dlnetwork (random init) matching the
% classifier input size. Used only to exercise the artifact plumbing; random
% weights mean no clinical claim is ever made.
    layers = [ ...
        imageInputLayer([224 224 3], 'Name', 'input'), ...
        convolution2dLayer(3, 4, 'Padding', 'same', 'Name', 'conv1'), ...
        reluLayer('Name', 'relu1'), ...
        fullyConnectedLayer(5, 'Name', 'fc'), ...
        softmaxLayer('Name', 'softmax')];
    net = dlnetwork(layerGraph(layers));
end

function artFile = writeArtifact(backbone, net)
%WRITEARTIFACT  Persist a test artifact under the gitignored data/models/.
    artFile = fullfile(paths().data.models, sprintf('%s_dr_aptos.mat', backbone));
    save(artFile, 'net', 'backbone');
end

function b = writeBenchmarkRecord(backbone)
%WRITEBENCHMARKRECORD  Temporarily record a chosen backbone so
% cfg.model.available becomes true (mirrors benchmark_backbones.m output).
    b.file = fullfile(paths().data.models, 'backbone_benchmark.json');
    b.present = exist(b.file, 'file') == 2;
    b.text = '';
    if b.present; b.text = fileread(b.file); end
    rec = struct('chosenBackbone', backbone, 'targetsMet', true);
    fid = fopen(b.file, 'w');
    fwrite(fid, jsonencode(rec)); fclose(fid);
end

function restoreAll(artFile, calArt, b)
    deleteIfExists(artFile);
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