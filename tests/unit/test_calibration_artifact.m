function tests = test_calibration_artifact
%TEST_CALIBRATION_ARTIFACT  Focused tests for calibration persistence/loading.
%
%   P0 backend wiring (docs/ARCHITECTURE.md §3.7 / §8): the fitted temperature
%   T from calibration/fitTemperature.m must be persisted to
%   data/models/<backbone>_calib.mat (calibration/saveCalibration.m), loaded by
%   core/loadCalibration.m, and passed to calibration/applyCalibration.m by
%   scripts/runPipeline.m in real-model mode — never replaced by the identity
%   T=1 when a real calibration artifact exists. The honest mock path keeps
%   the config identity T.
%
%   Run:  results = runtests('tests/unit/test_calibration_artifact')
%
%   The pipeline end-to-end test needs the Deep Learning Toolbox; without it it
%   is skipped with a warning. Persistence/error-path tests run everywhere.

    tests = functiontests(localfunctions);
end

% =====================================================================
%  Save / load round-trip (no DL toolbox required)
% =====================================================================

function testValidTSaveLoad(testCase)
    artFile = fullfile(paths().data.models, 'cal_rt_dr_calib.mat');
    cleanup = onCleanup(@() deleteIfExists(artFile));
    filepath = saveCalibration(2.5, 'cal_rt_dr');
    verifyTrue(testCase, strcmp(filepath, artFile) || exist(filepath, 'file') == 2);
    cfg = struct('model', struct('backbone', 'cal_rt_dr', 'available', true));
    T = loadCalibration(cfg);
    verifyEqual(testCase, T, 2.5);
end

% =====================================================================
%  Missing / invalid artifact (no DL toolbox required)
% =====================================================================

function testMissingArtifactRaises(testCase)
    cfg = struct('model', struct('backbone', 'no_such_cal', 'available', true));
    verifyError(testCase, @() loadCalibration(cfg), ...
        'RetinaSense:loadCalibration:MissingArtifact');
end

function testMissingBackboneRaises(testCase)
    cfg = struct('model', struct('backbone', '', 'available', true));
    verifyError(testCase, @() loadCalibration(cfg), ...
        'RetinaSense:loadCalibration:MissingModel');
end

function testInvalidTemperatureSaveRaises(testCase)
    verifyError(testCase, @() saveCalibration(0, 'cal_bad'), ...
        'RetinaSense:saveCalibration:InvalidTemperature');
    verifyError(testCase, @() saveCalibration(-1, 'cal_bad'), ...
        'RetinaSense:saveCalibration:InvalidTemperature');
    verifyError(testCase, @() saveCalibration(NaN, 'cal_bad'), ...
        'RetinaSense:saveCalibration:InvalidTemperature');
    verifyError(testCase, @() saveCalibration([1 2], 'cal_bad'), ...
        'RetinaSense:saveCalibration:InvalidTemperature');
end

function testMissingBackboneSaveRaises(testCase)
    verifyError(testCase, @() saveCalibration(2.0, ''), ...
        'RetinaSense:saveCalibration:MissingBackbone');
end

function testInvalidArtifactLoadRaises(testCase)
    % Present but without variable T -> InvalidArtifact.
    artFile = fullfile(paths().data.models, 'cal_novar_dr_calib.mat');
    cleanup = onCleanup(@() deleteIfExists(artFile));
    foo = 1;
    save(artFile, 'foo');
    cfg = struct('model', struct('backbone', 'cal_novar_dr', 'available', true));
    verifyError(testCase, @() loadCalibration(cfg), ...
        'RetinaSense:loadCalibration:InvalidArtifact');
end

function testInvalidTemperatureLoadRaises(testCase)
    % Present, has T, but T is not a positive finite scalar -> InvalidTemperature.
    artFile = fullfile(paths().data.models, 'cal_badtemp_dr_calib.mat');
    cleanup = onCleanup(@() deleteIfExists(artFile));
    T = 0;
    save(artFile, 'T');
    cfg = struct('model', struct('backbone', 'cal_badtemp_dr', 'available', true));
    verifyError(testCase, @() loadCalibration(cfg), ...
        'RetinaSense:loadCalibration:InvalidTemperature');
end

% =====================================================================
%  Mock path unchanged (no DL toolbox required)
% =====================================================================

function testMockPathUnchanged(testCase)
% Default runPipeline (mock=true) keeps the config identity T=1: calibrated
% probabilities equal the mock raw probabilities.
    c = runPipeline('scenario', 'good');
    verifyEqual(testCase, c.grading.modelFile, '');
    verifyEqual(testCase, c.calibrated.calibratedProbs, ...
        applyCalibration(c.grading, 1.0, experiment_config().calibration).calibratedProbs, ...
        'AbsTol', 1e-12);
end

% =====================================================================
%  Pipeline passes loaded T (requires Deep Learning Toolbox)
% =====================================================================

function testPipelinePassesLoadedT(testCase)
% With a benchmark-recorded backbone + net + calibration artifacts, runPipeline
% must hand the persisted T (=2.5) to applyCalibration — not the identity.
    if ~isToolboxAvailable()
        warning('test_calibration_artifact:skip', ...
            'Deep Learning Toolbox unavailable; skipping pipeline-pass-T test.');
        return;
    end
    net = makeTestNet();
    netArt = writeArtifact('cal_pipe_test', net);
    saveCalibration(2.5, 'cal_pipe_test');
    bench  = writeBenchmarkRecord('cal_pipe_test');
    cleanup = onCleanup(@() restoreAll(netArt, ...
        fullfile(paths().data.models, 'cal_pipe_test_calib.mat'), bench));

    c = runPipeline('scenario', 'good', 'mock', false);

    % Deterministic check: applyCalibration is pure; the pipeline output must
    % match a local call with the persisted T=2.5 (would differ for T=1).
    expected = applyCalibration(c.grading, 2.5, experiment_config().calibration);
    verifyEqual(testCase, c.calibrated.calibratedProbs, expected.calibratedProbs, ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, c.calibrated.confidence, expected.confidence, 'AbsTol', 1e-12);
    verifyEqual(testCase, c.calibrated.uncertainty, expected.uncertainty, 'AbsTol', 1e-12);
    verifyTrue(testCase, islogical(c.calibrated.reviewRequired));
end

% =====================================================================
%  Helpers
% =====================================================================

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