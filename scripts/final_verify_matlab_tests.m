% final_verify_matlab_tests.m
% Adds repo folders (excluding frontend/backend node deps) and runs the
% existing MATLAB unit + integration test suite.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(root, 'analysis')));
addpath(genpath(fullfile(root, 'calibration')));
addpath(genpath(fullfile(root, 'classification')));
addpath(genpath(fullfile(root, 'config')));
addpath(genpath(fullfile(root, 'core')));
addpath(genpath(fullfile(root, 'database')));
addpath(genpath(fullfile(root, 'dataset')));
addpath(genpath(fullfile(root, 'evaluation')));
addpath(genpath(fullfile(root, 'explainability')));
addpath(genpath(fullfile(root, 'preprocessing')));
addpath(genpath(fullfile(root, 'reporting')));
addpath(genpath(fullfile(root, 'scripts')));
addpath(genpath(fullfile(root, 'simulink')));
addpath(genpath(fullfile(root, 'ui')));
addpath(genpath(fullfile(root, 'tests')));

ru = runtests(fullfile(root, 'tests', 'unit'));
ri = runtests(fullfile(root, 'tests', 'integration'));
results = [ru ri];
disp(runtests_summary(results));

function summary = runtests_summary(results)
    summary = table();
    summary.Name = {results.Name}.';
    summary.Passed = [results.Passed].';
    summary.Failed = [results.Failed].';
    summary.Incomplete = [results.Incomplete].';
    nPass = sum([results.Passed]);
    nFail = sum([results.Failed]);
    nIncm = sum([results.Incomplete]);
    fprintf('\n==== MATLAB TEST TOTALS: %d passed, %d failed, %d incomplete ====\n', nPass, nFail, nIncm);
    failed = results([results.Failed]);
    for i = 1:numel(failed)
        fprintf('FAILED: %s — %s\n', failed(i).Name, failed(i).Details.DiagnosticRecord.Report);
    end
end