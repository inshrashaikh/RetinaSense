function tests = test_metrics_artifact
%TEST_METRICS_ARTIFACT  Save/load of the {backbone}_metrics.mat artifact.
%
% Tests evaluation/saveMetrics.m + core/loadMetrics.m under the AGENTS.md
% honesty rule: only REAL module output (evaluation/metrics.m on genuine
% labels/preds/probs) is ever persisted; invalid or placeholder metrics are
% rejected; missing artifacts raise the documented RetinaSense identifiers.
%
% No network, no data split, no fabricated numbers in this test file.

    tests = functiontests(localfunctions);
end

% --------------------------------------------------------------------------
function testSaveLoadRoundTrip(testCase)
    b = tempBackbone(testCase);
    m = realMetricsContract(testCase);

    filepath = saveMetrics(m, b);
    testCase.verifyTrue(exist(filepath, 'file') > 0, ...
        'saveMetrics must persist the artifact.');

    cfg = experiment_config();
    cfg.model.backbone = b;
    loaded = loadMetrics(cfg);
    testCase.verifyEqual(loaded, m, 'AbsTol', 1e-12, ...
        'Type-checked metrics must round-trip unchanged.');
end

function testSaveLoadRealMetricsFromModule(testCase)
    % The artifact is built by the real metrics() module — no hand-picked
    % numbers. This is the only path audit-able as "real".
    b = tempBackbone(testCase);
    labels = [0 0 1 1 1 2 2 2 3 3 4 4 4 4 4]';
    preds  = [0 0 1 1 1 2 2 2 3 3 4 4 4 4 4]';
    probs  = rand(15, 5); probs = probs ./ sum(probs, 2);
    probs(labels + 1 == 1, :) = 0; probs(labels == 0, 1) = 1; % keep per-class sane
    m = metrics(labels, preds, probs);

    filepath = saveMetrics(m, b);
    cfg = experiment_config();
    cfg.model.backbone = b;
    loaded = loadMetrics(cfg);

    testCase.verifyEqual(loaded.n, m.n);
    testCase.verifyEqual(loaded.accuracy, m.accuracy, 'AbsTol', 1e-12);
    testCase.verifyEqual(loaded.confusion, m.confusion, 'AbsTol', 1e-12);
    testCase.verifyEqual(loaded.quadraticKappa, m.quadraticKappa, 'AbsTol', 1e-12);
    testCase.verifyTrue(exist(filepath, 'file') > 0);
end

function testRoundTripRejectsPlaceholder(testCase)
    % A hand-invented single-field "metrics" struct must NEVER be written.
    b = tempBackbone(testCase);
    fake = struct('accuracy', 0.95);          % not the contract -> placeholder
    testCase.verifyError(@() saveMetrics(fake, b), ...
        'RetinaSense:saveMetrics:InvalidMetrics', ...
        'Placeholder metrics must be rejected.');
    testCase.verifyFalse(exist(fullfile(paths().data.models, ...
        sprintf('%s_metrics.mat', b)), 'file') > 0, ...
        'No artifact may be written for rejected metrics.');
end

function testRejectsOutOfRangeAccuracy(testCase)
    b = tempBackbone(testCase);
    m = realMetricsContract(testCase);
    m.accuracy = 1.5;                         % not a real [0,1] metric value
    testCase.verifyError(@() saveMetrics(m, b), ...
        'RetinaSense:saveMetrics:InvalidMetrics');
end

function testRejectsOutOfRangeReferableSensitivity(testCase)
    b = tempBackbone(testCase);
    m = realMetricsContract(testCase);
    m.referableSensitivity = 2;               % outside [0,1] -> not module output
    testCase.verifyError(@() saveMetrics(m, b), ...
        'RetinaSense:saveMetrics:InvalidMetrics');
end

function testRejectsMalformedConfusion(testCase)
    b = tempBackbone(testCase);
    m = realMetricsContract(testCase);
    m.confusion = eye(4);                     % wrong contract shape
    testCase.verifyError(@() saveMetrics(m, b), ...
        'RetinaSense:saveMetrics:InvalidMetrics');
end

function testMissingBackbone(testCase)
    testCase.verifyError(@() saveMetrics(struct(), ''), ...
        'RetinaSense:saveMetrics:MissingBackbone');
end

function testMissingArtifact(testCase)
    cfg = experiment_config();
    cfg.model.backbone = 'no_such_backbone_xyz';
    testCase.verifyError(@() loadMetrics(cfg), ...
        'RetinaSense:loadMetrics:MissingArtifact');
end

function testMissingBackboneOnLoad(testCase)
    cfg = experiment_config();
    cfg.model.backbone = '';
    testCase.verifyError(@() loadMetrics(cfg), ...
        'RetinaSense:loadMetrics:MissingModel');
end

function testInvalidArtifactNoMetricsVar(testCase)
    b = tempBackbone(testCase);
    filepath = fullfile(paths().data.models, sprintf('%s_metrics.mat', b));
    somethingElse = struct('x', 1);               % written by the TEST, not a module
    save(filepath, 'somethingElse');
    testCase.addTeardown(@deleteIfExists, filepath);
    cfg = experiment_config();
    cfg.model.backbone = b;
    testCase.verifyError(@() loadMetrics(cfg), ...
        'RetinaSense:loadMetrics:InvalidArtifact');
end

function testInvalidMetricsOnLoad(testCase)
    % A hand-written .mat with a placeholder value is caught on load.
    b = tempBackbone(testCase);
    metrics = struct('accuracy', 0.9);        % placeholder, not module output
    filepath = fullfile(paths().data.models, sprintf('%s_metrics.mat', b));
    save(filepath, 'metrics');
    testCase.addTeardown(@deleteIfExists, filepath);
    cfg = experiment_config();
    cfg.model.backbone = b;
    testCase.verifyError(@() loadMetrics(cfg), ...
        'RetinaSense:loadMetrics:InvalidMetrics', ...
        'A stored placeholder must never be consumed as real metrics.');
end

function testZeroCountMetricsRejected(testCase)
    % n=0 means "nothing measured" — honest skip, never a persisted artifact.
    b = tempBackbone(testCase);
    m = realMetricsContract(testCase);
    m.n = 0;
    testCase.verifyError(@() saveMetrics(m, b), ...
        'RetinaSense:saveMetrics:InvalidMetrics');
end

function testNaNReferableAucAccepted(testCase)
    % Degenerate single-class split -> honest NaN (metrics.m). Must persist,
    % never be "fixed" with a number.
    b = tempBackbone(testCase);
    m = realMetricsContract(testCase);
    m.aucReferable = NaN;                     % genuine degenerate AUROC
    m.quadraticKappa = 1; m.ece = 0;
    m.accuracy = 1; m.referableSensitivity = 1; m.referableSpecificity = 1;
    m.confusion = diag([1 1 1 1 1]);
    filepath = saveMetrics(m, b);
    cfg = experiment_config();
    cfg.model.backbone = b;
    loaded = loadMetrics(cfg);
    testCase.verifyTrue(isnan(loaded.aucReferable));
    testCase.verifyTrue(exist(filepath, 'file') > 0);
end

% --------------------------------------------------------------------------
function m = realMetricsContract(~)
    % Valid contract-shaped metrics with sane values (used as a baseline
    % that tests then mutate for negative cases). Values are consistent, not
    % arbitrary fakes.
    m = struct( ...
        'n', 100, ...
        'confusion', diag([20 20 20 20 20]), ...
        'accuracy', 1, ...
        'perClassSensitivity', ones(1, 5), ...
        'perClassSpecificity', ones(1, 5), ...
        'referableSensitivity', 1, ...
        'referableSpecificity', 1, ...
        'aucReferable', 1, ...
        'quadraticKappa', 1, ...
        'ece', 0);
end

function b = tempBackbone(testCase)
    b = ['test_metrics_', strrep(num2str(rng_seed_value()), '.', '_')];
    filepath = fullfile(paths().data.models, sprintf('%s_metrics.mat', b));
    deleteIfExists(filepath);
    testCase.addTeardown(@deleteIfExists, filepath);
end

function r = rng_seed_value()
    r = sum(100 * clock);
end

function deleteIfExists(p)
    if exist(p, 'file') == 2; delete(p); end
end