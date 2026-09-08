function tests = test_config
%TEST_CONFIG  Unit tests for centralized configuration.
    tests = functiontests(localfunctions);
end

function test_qualityThresholds(testCase)
    q = quality_thresholds();
    verifyTrue(testCase, q.goodScore > q.borderlineScore);
    verifyTrue(testCase, q.weights.focus > 0);
    verifyEqual(testCase, size(q.metricLow, 1), 4);
    verifyEqual(testCase, size(q.metricMid, 1), 4);
end

function test_referThresholdIsLevel2(testCase)
    cfg = experiment_config();
    verifyEqual(testCase, cfg.referThreshold, 2);          % Level 2+ (PRD)
    verifyEqual(testCase, cfg.classification.referThreshold, 2);
end

function test_configNotHardcoded(testCase)
    cfg = experiment_config();
    verifyTrue(testCase, isfield(cfg, 'quality'));
    verifyTrue(testCase, isfield(cfg, 'preprocess'));
    verifyTrue(testCase, isfield(cfg, 'calibration'));
    verifyTrue(testCase, isfield(cfg, 'review'));
    verifyTrue(testCase, isfield(cfg.mock, 'enabled'));
end

function test_pathsCreatesDirs(testCase)
    p = paths();
    verifyTrue(testCase, isfield(p, 'data'));
    verifyTrue(testCase, exist(p.data.raw, 'dir') == 7);
    verifyTrue(testCase, exist(p.output, 'dir') == 7);
end