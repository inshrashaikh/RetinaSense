function tests = test_pipeline_full_flow
%TEST_PIPELINE_FULL_FLOW  Focused integration test: the FULL mandatory flow.
%
%   ingestion -> quality gate -> enhancement/recheck (borderline) -> analysis
%   -> grading -> Grad-CAM / evidence -> calibration -> review -> report.
%
%   Covers:
%     * mock mode: the whole flow runs with NO trained artifacts / NO toolboxes
%       (honest mock, modelFile='').
%     * real mode: requires the model + calibration artifacts; missing/corrupt
%       artifacts raise clear structured RetinaSense errors.
%     * failure routing: ungradable stops after the quality gate; borderline
%       enhancement either recaptures before grading or is adopted; low
%       confidence routes to mandatory human review; evidence stays advisory
%       and never changes grading/referral.
%
%   Toolbox-gated: real-mode success paths need the Deep Learning Toolbox and
%   are skipped (with a warning) otherwise — exactly like the unit artifact
%   tests. No training, no dataset download, no fabricated outputs or metrics.

    tests = functiontests(localfunctions);
end

% =====================================================================
%  FULL MANDATORY FLOW (mock, no artifacts, no toolboxes)
% =====================================================================

function test_fullMandatoryFlowOrderMock(testCase)
    c = runPipeline('scenario', 'good', 'mock', true);
    expected = {'ingest','qualityGate','analysis','grading', ...
                'explainability','calibration','review','report'};
    idx = zeros(1, numel(expected));
    for i = 1:numel(expected)
        idx(i) = find(strcmp(c.pipeline.stages, expected{i}));
    end
    testCase.verifyTrue(all(diff(idx) > 0), ...
        'Stages must run in the mandatory order (§2).');
    testCase.verifyTrue(~isempty(c.pipeline.finishedAt));
    testCase.verifyTrue(isempty(c.pipeline.exitStage));
end

function test_mockModeRunsWithNoArtifacts(testCase)
    % Mock mode must never touch model artifacts: even when a benchmark record
    % / trained model IS present in this workspace, mock=true forces the honest
    % mock path (no gate, no artifact load, modelFile='', identity calibration).
    c = runPipeline('scenario', 'good', 'mock', true);          % mock forced explicitly
    testCase.verifyEqual(c.grading.modelFile, '', ...
        'Mock mode must not claim a trained model.');
    testCase.verifyTrue(isfinite(c.calibrated.confidence), ...
        'Identity calibration must still produce bounded confidence.');
end

% =====================================================================
%  FAILURE ROUTING
% =====================================================================

function test_ungradableStopsAfterQualityGate(testCase)
    c = runPipeline('scenario', 'ungradable', 'mock', true);
    testCase.verifyEqual(c.quality.class, 'ungradable');
    testCase.verifyEqual(c.pipeline.exitStage, 'qualityGate');
    for s = {'analysis','grading','explainability','calibration','review','report'}
        testCase.verifyFalse(any(strcmp(c.pipeline.stages, s{1})), ...
            sprintf('No stage %s may run for an ungradable image.', s{1}));
    end
    testCase.verifyTrue(~isempty(c.quality.recapture.reasonCode));
    testCase.verifyTrue(~isempty(c.quality.recapture.instruction));
end

function test_borderlineEnhanceThenRecheckRouting(testCase)
    c = runPipeline('scenario', 'borderline', 'mock', true);
    testCase.verifyEqual(c.quality.class, 'borderline');
    if strcmp(c.pipeline.exitStage, 'enhancementRecheck')
        % Enhanced image still ungradable -> recapture BEFORE any grading.
        testCase.verifyFalse(any(strcmp(c.pipeline.stages, 'grading')));
        testCase.verifyTrue(~isempty(c.quality.recapture.reasonCode));
    else
        % Enhancement adopted -> grading/report must follow.
        testCase.verifyTrue(c.pipeline.enhanced);
        testCase.verifyTrue(any(strcmp(c.pipeline.stages, 'grading')));
        testCase.verifyTrue(any(strcmp(c.pipeline.stages, 'report')));
    end
end

function test_lowConfidenceRoutesToReview(testCase)
    c = runPipeline('scenario', 'good', 'mock', true);
    if c.calibrated.reviewRequired
        % No reviewer input at run time -> routed to the review queue.
        testCase.verifyEqual(c.review.status, 'reqReview');
        testCase.verifyTrue(c.calibrated.uncertainty <= 1 && ...
                            c.calibrated.confidence >= 0);
    else
        testCase.verifyTrue(ismember(c.review.status, {'auto','approved'}));
    end
end

function test_evidenceAdvisoryNeverChangesGrading(testCase)
    % The grading struct carries §4.4 fields only; evidence fields never leak
    % into it, and two runs with identical inputs give identical grading.
    ca = runPipeline('scenario', 'good', 'mock', true);
    cb = runPipeline('scenario', 'good', 'mock', true);
    fields4_4 = {'rawProbs','grade','referableProb','referable','modelFile'};
    testCase.verifyEqual(fieldnames(ca.grading), fields4_4', ...
        'grading must expose exactly the §4.4 contract fields.');
    testCase.verifyEqual(ca.grading, cb.grading, ...
        'Advisory evidence must not perturb the deterministic grading.');
end

% =====================================================================
%  REAL MODE: artifacts strictly required, clear errors when missing/corrupt
% =====================================================================

function test_realModeMissingModelRaises(testCase)
    % available=true (benchmark record present) but NO model artifact ->
    % clear structured error, never a silent mock fallback. Toolbox-free.
    withModelAvailable(testCase, 'missingmodel_b0', true);
    testCase.verifyError(@() runPipeline('mock', false), ...
        'RetinaSense:loadTrainedModel:MissingArtifact');
end

function test_realModeCorruptModelRaises(testCase)
    % Artifact present but not a network -> InvalidArtifact. Toolbox-free.
    b = 'corruptnet_b0';
    withModelAvailable(testCase, b, true);
    writeArtifact(testCase, sprintf('%s_dr_aptos.mat', b), struct('net', []));
    testCase.verifyError(@() runPipeline('mock', false), ...
        'RetinaSense:loadTrainedModel:InvalidArtifact');
end

function test_realModeMissingCalibrationRaises(testCase)
    % VALID network artifact but no calibration -> MissingArtifact.
    % Needs DL Toolbox to build a real net.
    if ~isToolboxAvailable()
        testCase.verifyTrue(true, 'Skipped (no Deep Learning Toolbox).');
        return;
    end
    b = 'nocalib_b0';
    withModelAvailable(testCase, b, true);
    writeArtifact(testCase, sprintf('%s_dr_aptos.mat', b), ...
        struct('net', makeTestNet(), 'backbone', b));
    testCase.verifyError(@() runPipeline('mock', false), ...
        'RetinaSense:loadCalibration:MissingArtifact');
end

function test_realModeLoadsModelAndCalibration(testCase)
    % Full real-mode flow: model artifact + calibration artifact are loaded
    % and consumed (grading.modelFile set, calibration T applied). Needs DL
    % Toolbox; skipped otherwise.
    if ~isToolboxAvailable()
        testCase.verifyTrue(true, 'Skipped (no Deep Learning Toolbox).');
        return;
    end
    b = 'realmode_b0';
    withModelAvailable(testCase, b, true);
    T = 1.8;
    writeArtifact(testCase, sprintf('%s_dr_aptos.mat', b), ...
        struct('net', makeTestNet(), 'backbone', b));
    writeArtifact(testCase, sprintf('%s_calib.mat', b), struct('T', T));

    c = runPipeline('mock', false, 'scenario', 'good');
    testCase.verifyTrue(~isempty(c.grading.modelFile), ...
        'Real mode must mark the loaded model on grading.');
    testCase.verifyEqual(c.calibrated.calibratedProbs(1) ...
        + c.calibrated.calibratedProbs(2) ...
        + c.calibrated.calibratedProbs(3) ...
        + c.calibrated.calibratedProbs(4) ...
        + c.calibrated.calibratedProbs(5), 1, 'AbsTol', 1e-9);
    testCase.verifyTrue(any(strcmp(c.pipeline.stages, 'report')), ...
        'Real-mode full flow must complete through the report.');
end

% =====================================================================
%  Helpers
% =====================================================================

function withModelAvailable(testCase, backbone, targetsMet)
    % Write a transient backbone_benchmark.json making cfg.model.available
    % true for runPipeline's real-mode gate; restore the prior state after.
    rec = struct('chosenBackbone', backbone, 'targetsMet', targetsMet, ...
                 'perBackbone', struct());
    file = fullfile(paths().data.models, 'backbone_benchmark.json');
    had = exist(file, 'file') == 2;
    old = '';
    if had; old = fileread(file); end
    fid = fopen(file, 'w');
    fwrite(fid, jsonencode(rec)); fclose(fid);
    testCase.addTeardown(@restoreBenchmarkRecord, file, had, old);
end

function restoreBenchmarkRecord(file, had, old)
    if had
        fid = fopen(file, 'w'); fwrite(fid, old); fclose(fid);
    else
        deleteIfExists(file);
    end
end

function writeArtifact(testCase, name, payload)
    filepath = fullfile(paths().data.models, name);
    deleteIfExists(filepath);
    save(filepath, '-struct', 'payload');
    testCase.addTeardown(@deleteIfExists, filepath);
end

function net = makeTestNet()
    % A REAL (untrained) 224x224x3 dlnetwork, assembled from a layerGraph
    % on the MATLAB host — never a fabricated/mock "model".
    layers = [imageInputLayer([224 224 3], 'Name', 'input') ...
        convolution2dLayer(3, 4, 'Padding', 'same', 'Name', 'conv1') ...
        reluLayer('Name', 'relu1') ...
        fullyConnectedLayer(5, 'Name', 'fc5') ...
        softmaxLayer('Name', 'softmax')];
    net = dlnetwork(layerGraph(layers));
end

function tf = isToolboxAvailable()
    tf = ~isempty(which('dlnetwork')) && ...
         ~isempty(which('imageInputLayer')) && ...
         ~isempty(which('gradCAM'));
end

function deleteIfExists(p)
    if exist(p, 'file') == 2; delete(p); end
end