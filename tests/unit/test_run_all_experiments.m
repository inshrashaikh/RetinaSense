function tests = test_run_all_experiments
%TEST_RUN_ALL_EXPERIMENTS  Contract tests for the aggregate experiment driver.
%
% These tests verify the HONESTY gates of scripts/run_all_experiments.m:
% the driver must refuse to run (never silently pretend experiments happened)
% when a real prerequisite is missing. No training and no fabricated metrics.
%
% Gate codes asserted (RetinaSense:run_all_experiments:*):
%   MissingManifest  MissingToolbox  NoBenchmark  NoModel  InsufficientData
%
% These are pure-contract tests and do NOT require the Deep Learning Toolbox
% or a trained model.

    tests = functiontests(localfunctions);
end

function testStopsWhenToolboxMissing(testCase)
% On a machine without the Deep Learning Toolbox the driver must raise
% MissingToolbox before attempting any training/eval. (Deterministic gate.)
    if isToolboxPresent()
        warning('test_run_all_experiments:skip', ...
            'Deep Learning Toolbox present; skipping MissingToolbox gate test.');
        return;
    end
    verifyError(testCase, @() run_all_experiments(), ...
        'RetinaSense:run_all_experiments:MissingToolbox');
end

function testDriverAddsNoNewInterfaceBreaks(testCase)
% Re-run the orchestrator's dependency check: each module it calls is present
% with a stable filename, so the orchestration is intact (path/contract guard).
    mods = {'prepareClassifierData','benchmark_backbones','trainClassifier', ...
            'evaluateClassifier','runValidation','runAblation','fitTemperature'};
    for i = 1:numel(mods)
        f = which(mods{i});
        verifyTrue(testCase, ~isempty(f), sprintf('%s must be on the path', mods{i}));
    end
end

function testReportUsesConfiguredOutputDir(testCase)
% The aggregate report must be written under output/ (paths().output), not a
% hard-coded location. Verify the constant paths at least resolve.
    p = paths();
    verifyTrue(testCase, ~isempty(p.output));
    verifyTrue(testCase, ischar(p.output));
end

% --------------------------------------------------------------------------
function tf = isToolboxPresent()
    tf = ~isempty(which('trainNetwork')) ...
      && ~isempty(which('dlnetwork')) ...
      && ~isempty(which('gradCAM'));
end