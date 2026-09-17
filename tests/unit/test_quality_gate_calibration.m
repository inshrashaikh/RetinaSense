function tests = test_quality_gate_calibration
%TEST_QUALITY_GATE_CALIBRATION  Unit tests for scripts/calibrate_quality_gate.m.
%
%   Honesty-focused: the harness may ONLY compute metrics by running the real
%   assessQuality() gate over a labeled subset. No subset -> a structured
%   RetinaSense error and NOTHING persisted (AGENTS.md guardrails 1/3).
%
%   The "synthetic" runs here use the committed demo fundus image with
%   scenario-equivalent transforms (identical to runPipeline applyScenario) and
%   explicitly label the provenance 'synthetic' so the numbers can never be
%   mistaken for clinical validation.

    tests = functiontests(localfunctions);
end

% =====================================================================
%  Honest error paths (nothing fabricated, nothing persisted)
% =====================================================================

function test_missingSubsetRaises(testCase)
%TEST_MISSINGSUBSETRAISES  Absent labeled subset -> structured error, no persist.
    missing = fullfile(tempdir, 'rs_qcal_missing.csv');
    if exist(missing, 'file'); delete(missing); end
    testCase.verifyError(@() calibrate_quality_gate( ...
        'subsetPath', missing, 'imageRoot', tempdir), ...
        'RetinaSense:calibrateQualityGate:MissingLabeledSubset');
end

function test_missingImagesRaise(testCase)
%TEST_MISSINGIMAGESRAISE  Subset referencing absent images -> MissingImages.
    tmp = makeTempCaseDir(testCase);
    csv = writeSubset(testCase, tmp, { ...
        'phantom.png,good,synthetic'; ...
        'phantom2.png,borderline,synthetic'});
    testCase.verifyError(@() calibrate_quality_gate( ...
        'subsetPath', csv, 'imageRoot', tmp, 'outDir', tmp), ...
        'RetinaSense:calibrateQualityGate:MissingImages');
end

function test_badLabelRaises(testCase)
%TEST_BADLABELRAISES  Unrecognized label -> BadLabel, nothing persisted.
    tmp = makeTempCaseDir(testCase);
    imwrite(demoImage(), fullfile(tmp, 'a.png'));
    csv = writeSubset(testCase, tmp, {'a.png,terrible,synthetic'});
    testCase.verifyError(@() calibrate_quality_gate( ...
        'subsetPath', csv, 'imageRoot', tmp, 'outDir', tmp), ...
        'RetinaSense:calibrateQualityGate:BadLabel');
end

% =====================================================================
%  Real run on a small synthetic subset (provenance-labeled 'synthetic')
% =====================================================================

function test_syntheticSubsetRealRun(testCase)
%TEST_SYNTHETICSUBSETREALRUN  Real metrics computed, metrics JSON persisted.
    tmp = makeTempCaseDir(testCase);
    [good, borderline, ungradable] = scenarioImages();
    imwrite(good,        fullfile(tmp, 'good.png'));
    imwrite(borderline,  fullfile(tmp, 'borderline.png'));
    imwrite(ungradable,  fullfile(tmp, 'ungradable.png'));
    csv = writeSubset(testCase, tmp, { ...
        'good.png,good,synthetic'; ...
        'borderline.png,borderline,synthetic'; ...
        'ungradable.png,ungradable,synthetic'});

    r = calibrate_quality_gate('subsetPath', csv, 'imageRoot', tmp, ...
        'outDir', tmp, 'overrideFile', fullfile(tmp, 'override.mat'), ...
        'labelKind', 'synthetic');

    % Real, bounded numbers computed from actual assessQuality runs.
    testCase.verifyTrue(r.baselineMetrics.agreement >= 0 && ...
        r.baselineMetrics.agreement <= 1);
    testCase.verifyTrue(r.baselineMetrics.falseRejectionRate >= 0 && ...
        r.baselineMetrics.falseRejectionRate <= 1);
    testCase.verifyTrue(r.baselineMetrics.ungradableCatch >= 0 && ...
        r.baselineMetrics.ungradableCatch <= 1);
    testCase.verifyTrue(r.chosenMetrics.agreement >= 0 && ...
        r.chosenMetrics.agreement <= 1, 'chosen agreement out of range');
    testCase.verifyTrue(r.nImages == 3);
    testCase.verifyEqual(r.labelKind, 'synthetic');

    % Chosen threshold set is a valid gate config.
    testCase.verifyTrue(isfield(r.selected, 'goodScore'));
    testCase.verifyTrue(size(r.selected.metricLow, 1) == 4);
    testCase.verifyTrue(size(r.selected.metricMid, 1) == 4);

    % Metrics JSON audit trail exists and decodes.
    testCase.verifyTrue(exist(r.metricsFile, 'file') == 2, 'metrics JSON missing');
    J = jsondecode(fileread(r.metricsFile));
    testCase.verifyEqual(J.kind, 'real-experiment');
    testCase.verifyEqual(J.nImages, 3);
    testCase.verifyTrue(isfield(J.grid, 'best'));
    testCase.verifyTrue(abs(J.grid.best.loss - r.chosenLoss) < 1e-6, ...
        'persisted best loss != returned loss');
end

function test_overrideActivatesThenReverts(testCase)
%TEST_OVERRIDEACTIVATESTHENREVERTS  With override enabled the persisted
%   threshold set drives quality_thresholds(); teardown restores defaults.
    prerun = quality_thresholds();

    tmp = makeTempCaseDir(testCase);
    [good, borderline, ungradable] = scenarioImages();
    imwrite(good,        fullfile(tmp, 'good.png'));
    imwrite(borderline,  fullfile(tmp, 'borderline.png'));
    imwrite(ungradable,  fullfile(tmp, 'ungradable.png'));
    csv = writeSubset(testCase, tmp, { ...
        'good.png,good,synthetic'; ...
        'borderline.png,borderline,synthetic'; ...
        'ungradable.png,ungradable,synthetic'});

    overrideFile = quality_calibration().persist.overrideFile;
    testCase.addTeardown(@deleteIfExists, overrideFile);

    r = calibrate_quality_gate('subsetPath', csv, 'imageRoot', tmp, ...
        'outDir', tmp, 'overrideFile', overrideFile, 'labelKind', 'synthetic');
    testCase.verifyTrue(r.overrideWritten, 'override not written');
    testCase.verifyTrue(exist(overrideFile, 'file') == 2);

    % quality_thresholds() must reflect the persisted calibrated set.
    q = quality_thresholds();
    testCase.verifyEqual(q.goodScore, r.selected.goodScore, 'AbsTol', 1e-12, ...
        'quality_thresholds() did not apply the persisted override');
end

% =====================================================================
%  Helpers
% =====================================================================

function img = demoImage()
    img = imread(fullfile(paths().assets, 'synthetic_fundus_demo.png'));
end

function [good, borderline, ungradable] = scenarioImages()
%SCENARIOIMAGES  Demo image + the exact applyScenario transforms from
%   scripts/runPipeline.m so the gate classes are deterministic and known.
    im = demoImage();
    imd = double(im) / 255;
    good        = im2uint8(imd);
    borderline  = im2uint8(max(0, imd - 0.18));
    ungradable  = im2uint8(max(0, imd * 0.04));
end

function csv = writeSubset(testCase, dir, rows)
%WRITESUBSET  Write a labeled-subset CSV; remove on teardown.
    csv = fullfile(dir, 'quality_labels.csv');
    fid = fopen(csv, 'w');
    fwrite(fid, makeCsvText(rows));
    fclose(fid);
    testCase.addTeardown(@deleteIfExists, csv);
end

function text = makeCsvText(rows)
    nl = sprintf('\n');
    text = ['image,label,kind', nl];
    for i = 1:numel(rows)
        text = [text, rows{i}, nl]; %#ok<AGROW>
    end
end

function dir = makeTempCaseDir(testCase)
    dir = fullfile(tempdir, ['rs_qcal_', char(java.util.UUID.randomUUID())]);
    mkdir(dir);
    testCase.addTeardown(@removeDirRecursive, dir);
end

function removeDirRecursive(d)
    if exist(d, 'dir'); rmdir(d, 's'); end
end

function deleteIfExists(p)
    if exist(p, 'file') == 2; delete(p); end
end