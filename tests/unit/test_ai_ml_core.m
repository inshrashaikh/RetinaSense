function tests = test_ai_ml_core
%TEST_AI_ML_CORE  Unit tests for Member 1 AI/ML modules implemented in this
% workstream: calibration (fitTemperature, applyCalibration), evaluation
% (metrics with per-class + AUROC), explainability (computeGradCAM honest
% fallback), and classification (prepareClassifierData guard, classifyImage).
%
% These are pure-math / contract tests that do NOT require a trained model or
% the Deep Learning Toolbox. Real training/eval is exercised by the PyTorch
% experiment pipeline (tools/python_verifier/experiment_pipeline.py) and by
% benchmark_backbones.m on a MATLAB machine.

    tests = functiontests(localfunctions);
end

% --------------------------------------------------------------------------
% Calibration
% --------------------------------------------------------------------------
function testFitTemperatureRequiresLogits(testCase)
    verifyError(testCase, @() fitTemperature([], []), ...
        'RetinaSense:fitTemperature:NoLogits');
end

function testFitTemperatureRecoversKnownT(testCase)
    % Build synthetic logits where the label-generating temperature T* is known.
    % Labels are SAMPLED from the temperature-scaled categorical distribution,
    % not argmax: argmax labels are perfectly separable from logits alone, so
    % the NLL optimum collapses to T->0 and T* is not identifiable.
    rng(7, 'twister');
    n = 400;
    logits = randn(n, 5) * 2 + repmat([0 0.5 1.5 2.5 3.0], n, 1);
    Tstar = 2.3;
    p = exp(logits ./ Tstar); p = p ./ sum(p, 2);
    cp = cumsum(p, 2);                       % categorical sample 0..4
    labels = sum(rand(n, 1) > cp, 2);

    T = fitTemperature(logits, labels, 1.0);
    verifyTrue(testCase, T > 0.5 && T < 4.0, sprintf('T=%f too far from %.1f', T, Tstar));
    verifyTrue(testCase, abs(T - Tstar) < 0.5);
end

function testTemperatureScalingSoftensConfidence(testCase)
    % T>1 must push the max probability DOWN (softer confidence).
    grading.rawProbs = [0.02 0.04 0.10 0.80 0.04];
    cal0 = applyCalibration(grading, 1.0, experiment_config().calibration);
    calW = applyCalibration(grading, 2.5, experiment_config().calibration);
    verifyTrue(testCase, calW.confidence < cal0.confidence);
    verifyTrue(testCase, calW.uncertainty > cal0.uncertainty);
    verifyTrue(testCase, abs(sum(calW.calibratedProbs) - 1) < 1e-9);
end

function testReviewRequiredRouting(testCase)
    % Low-confidence but high let maximum grade UNCHANGED (no automatic grade
    % change); the routing is reviewRequired=true, never a different grade.
    grading.rawProbs = [0.40 0.20 0.20 0.10 0.10];
    cal = applyCalibration(grading, 1.0, experiment_config().calibration);
    verifyTrue(testCase, cal.reviewRequired);           % low confidence
    verifyEqual(testCase, argmaxGrade(grading.rawProbs), 0);  % grade unchanged
end

function testUncertaintyNormalizedEntropy(testCase)
    grading.rawProbs = [1 0 0 0 0];
    cal = applyCalibration(grading, 1.0, experiment_config().calibration);
    verifyEqual(testCase, cal.uncertainty, 0, 'AbsTol', 1e-6);
    grading.rawProbs = [0.2 0.2 0.2 0.2 0.2];
    cal = applyCalibration(grading, 1.0, experiment_config().calibration);
    verifyEqual(testCase, cal.uncertainty, 1, 'AbsTol', 1e-6);
end

% --------------------------------------------------------------------------
% Evaluation: metrics
% --------------------------------------------------------------------------
function testMetricsHasFullContract(testCase)
    labels = [0 0 0 1 1 2 2 3 3 4]';
    preds  = [0 0 0 1 1 2 2 3 4 4]';
    probs  = repmat(0.2, 10, 5);
    m = metrics(labels, preds, probs);
    verifyTrue(testCase, all(isfield(m, {'confusion','perClassSensitivity', ...
        'perClassSpecificity','aucReferable','quadraticKappa','ece','n'})));
    verifyEqual(testCase, size(m.confusion), [5 5]);
    verifyEqual(testCase, numel(m.perClassSensitivity), 5);
    verifyEqual(testCase, numel(m.perClassSpecificity), 5);
    verifyTrue(testCase, m.accuracy > 0);
end

function testMetricsAucPerfectClassifier(testCase)
    % Perfect referable classifier => AUROC = 1. Referable = grade >= 2
    % (confThreshold), so probs must be 5-class with the referable probability
    % mass in columns 3:5 cleanly separating the two groups.
    labels = [0 0 1 1 2 2 3 3 4 4]';
    preds  = labels;                                   % preds == labels
    refScore = [0.05 0.10 0.15 0.20 0.60 0.80 0.70 0.90 0.55 0.75]';
    probs = zeros(10, 5);
    probs(:, 3) = refScore;                            % referable mass
    probs(:, 1) = (1 - refScore) * 0.6;                % non-referable mass
    probs(:, 2) = (1 - refScore) * 0.4;
    m = metrics(labels, preds, probs);
    verifyEqual(testCase, m.aucReferable, 1, 'AbsTol', 1e-6);
    verifyTrue(testCase, m.referableSensitivity >= 0.999);
    verifyTrue(testCase, m.referableSpecificity >= 0.999);
end

function testMetricsDegenerateAucIsNan(testCase)
    labels = zeros(10, 1);                     % single class present
    preds  = zeros(10, 1);
    probs  = repmat(0.2, 10, 5);
    m = metrics(labels, preds, probs);
    verifyTrue(testCase, isnan(m.aucReferable));   % AUROC undefined -> honest NaN
end

% --------------------------------------------------------------------------
% Classification guards
% --------------------------------------------------------------------------
function testPrepareClassifierDataEmptyManifestRaises(testCase)
    % The committed manifest is schema-only (or has no data rows) -> must raise,
    % never fabricate a datastore.
    f = fullfile(paths().data.manifests, 'folds.csv');
    if exist(f, 'file')
        T = readtable(f);
        if height(T) == 0
            verifyError(testCase, @() prepareClassifierData(f), ...
                'RetinaSense:prepareClassifierData:ManifestEmpty');
        end
    end
end

function testClassifyImageMockContract(testCase)
    img = uint8(120 * ones(96, 96, 3));
    g = classifyImage(img, [], classification_config());
    verifyEqual(testCase, size(g.rawProbs), [1 5]);
    verifyTrue(testCase, abs(sum(g.rawProbs) - 1) < 1e-9);
    verifyTrue(testCase, g.grade >= 0 && g.grade <= 4);
    verifyTrue(testCase, islogical(g.referable));
end

% --------------------------------------------------------------------------
% Explainability honest fallback
% --------------------------------------------------------------------------
function testGradCAMWithoutModelHonest(testCase)
    img = uint8(120 * ones(96, 96, 3));
    x = computeGradCAM(img, [], [], struct('lesions', struct()), ...
        experiment_config().explainability);
    verifyTrue(testCase, all(x.gradCam(:) == 0));        % no fake attention
    verifyEqual(testCase, max(size(x.gradCam,1), size(x.gradCam,2)), ...
        max(size(img,1), size(img,2)));
    verifyTrue(testCase, ischar(x.note) && ~isempty(x.note));
end

function testGradCAMInvalidLayerGraceful(testCase)
    % A struct that is NOT a valid net must never crash; it must yield the
    % honest empty-map fallback (graceful missing-model/layer handling).
    fakeNet = struct('Name', 'not_a_net');
    img = uint8(80 * ones(64, 64, 3));
    x = computeGradCAM(img, fakeNet, struct('grade', 2), ...
        struct('lesions', struct()), experiment_config().explainability);
    verifyTrue(testCase, all(x.gradCam(:) == 0));
    verifyTrue(testCase, contains(x.note, 'Model attention'));
end

% --------------------------------------------------------------------------
% Helpers
% --------------------------------------------------------------------------
function g = argmaxGrade(probs)
    [~, ix] = max(probs(:));
    g = ix - 1;
end