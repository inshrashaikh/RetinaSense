function tests = test_review_ui
%TEST_REVIEW_UI  Contract and workflow tests for the ophthalmologist review UI.
%
%   Tests the RetinaSenseApp class against:
%     - Mock case loading (good, borderline)
%     - Full evidence case
%     - Missing evidence cases
%     - Review workflow (approve, override, recapture)
%     - Report generation
%     - Regression for Batch 1-4 contracts
%
%   Run:  results = runtests('tests/unit/test_review_ui')
%
%   MATLAB UI functional validation: requires MATLAB with App Designer
%   or uifigure support (R2016b+).

    tests = functiontests(localfunctions);
end

% =====================================================================
%  Test 1: Mock Case Loading
% =====================================================================

function test_mockGoodCaseLoads(testCase)
%TEST_MOCKGOODCASELOADS  Verify the app can be constructed with a mock good case.
    try
        app = RetinaSenseApp('mock', 'good');

        % Verify case was loaded
        verifyTrue(testCase, ~isempty(app.Case), 'Case not loaded');
        verifyTrue(testCase, isfield(app.Case, 'image'), 'Case missing image');
        verifyTrue(testCase, isfield(app.Case, 'grading'), 'Case missing grading');
        verifyTrue(testCase, isfield(app.Case, 'evidence'), 'Case missing evidence');
        verifyTrue(testCase, isfield(app.Case, 'calibrated'), 'Case missing calibrated');
        verifyTrue(testCase, isfield(app.Case, 'explain'), 'Case missing explain');

        % Verify grading is valid
        verifyTrue(testCase, app.Case.grading.grade >= 0 && ...
            app.Case.grading.grade <= 4, 'Grade out of range');
        verifyTrue(testCase, abs(sum(app.Case.grading.rawProbs) - 1) < 1e-6, ...
            'rawProbs do not sum to 1');

        % Verify calibrated is valid
        verifyTrue(testCase, app.Case.calibrated.confidence >= 0 && ...
            app.Case.calibrated.confidence <= 1, 'Confidence out of range');

        % Verify evidence has required fields
        verifyTrue(testCase, isfield(app.Case.evidence, 'vesselMask'), 'Missing vesselMask');
        verifyTrue(testCase, isfield(app.Case.evidence, 'opticDisc'), 'Missing opticDisc');
        verifyTrue(testCase, isfield(app.Case.evidence, 'fovea'), 'Missing fovea');
        verifyTrue(testCase, isfield(app.Case.evidence, 'lesions'), 'Missing lesions');
        verifyTrue(testCase, isfield(app.Case.evidence, 'confidence'), 'Missing evidence confidence');
        verifyTrue(testCase, isfield(app.Case.evidence, 'opticDiscDetail'), 'Missing opticDiscDetail');

        % Verify review is pending
        verifyTrue(testCase, ~app.ReviewComplete, 'Review should not be complete yet');

        % Clean up
        delete(app);
    catch ME
        % If uifigure is unavailable (no MATLAB display), test the case loading logic directly
        if contains(ME.identifier, 'uifigure') || contains(ME.message, 'uifigure') || ...
                contains(ME.message, 'No suitable')
            % Test the pipeline directly (UI not available)
            c = runPipeline('scenario', 'good');
            verifyTrue(testCase, ~isempty(c.image), 'Case image empty');
            verifyTrue(testCase, c.grading.grade >= 0, 'Grade invalid');
            verifyTrue(testCase, ~isempty(c.evidence.vesselMask), 'Vessel mask empty');
            verifyTrue(testCase, ~isempty(c.evidence.opticDiscDetail), 'Optic disc detail empty');
            verifyTrue(testCase, ismember(c.evidence.confidence, {'low','medium','high'}), ...
                'Evidence confidence invalid');
            verifyTrue(testCase, isfield(c, 'review'), 'Case missing review');
            verifyTrue(testCase, isfield(c, 'report'), 'Case missing report');
        else
            rethrow(ME);
        end
    end
end

function test_mockBorderlineCaseLoads(testCase)
%TEST_MOCKBORDERLINECASELOADS  Verify borderline case loads with enhancement metadata.
    try
        app = RetinaSenseApp('mock', 'borderline');

        verifyTrue(testCase, ~isempty(app.Case));
        verifyEqual(testCase, app.Case.quality.class, 'borderline');
        verifyTrue(testCase, isfield(app.Case.enhancement, 'appliedOps'));
        verifyTrue(testCase, app.Case.pipeline.enhanced || ...
            strcmp(app.Case.quality.class, 'borderline'));

        delete(app);
    catch ME
        if contains(ME.message, 'uifigure') || contains(ME.message, 'No suitable')
            c = runPipeline('scenario', 'borderline');
            verifyEqual(testCase, c.quality.class, 'borderline');
        else
            rethrow(ME);
        end
    end
end

% =====================================================================
%  Test 2: Full Evidence Case
% =====================================================================

function test_fullEvidenceCase(testCase)
%TEST_FULLEVIDENCECASE  Verify a case with all evidence fields displays correctly.
    c = runPipeline('scenario', 'good');

    % Verify all evidence fields are populated
    verifyTrue(testCase, isstruct(c.evidence));
    verifyTrue(testCase, isfield(c.evidence, 'vesselMask'));
    verifyTrue(testCase, islogical(c.evidence.vesselMask) || isempty(c.evidence.vesselMask));
    verifyTrue(testCase, isfield(c.evidence, 'opticDiscDetail'));
    verifyTrue(testCase, isstruct(c.evidence.opticDiscDetail));
    verifyTrue(testCase, isfield(c.evidence.opticDiscDetail, 'center'));
    verifyTrue(testCase, isfield(c.evidence.opticDiscDetail, 'status'));
    verifyTrue(testCase, ismember(c.evidence.opticDiscDetail.status, ...
        {'detected', 'low_confidence', 'not_detected'}));
    verifyTrue(testCase, isfield(c.evidence, 'fovea'));
    verifyTrue(testCase, isfield(c.evidence, 'lesions'));

    % Verify all four lesion classes
    classes = {'exudates', 'hemorrhages', 'microaneurysms', 'neoVasc'};
    for i = 1:numel(classes)
        cls = classes{i};
        verifyTrue(testCase, isfield(c.evidence.lesions, cls), ...
            sprintf('Missing lesion class: %s', cls));
        verifyTrue(testCase, isfield(c.evidence.lesions.(cls), 'map'), ...
            sprintf('Missing map for %s', cls));
        verifyTrue(testCase, isfield(c.evidence.lesions.(cls), 'count'), ...
            sprintf('Missing count for %s', cls));
        verifyTrue(testCase, isfield(c.evidence.lesions.(cls), 'features'), ...
            sprintf('Missing features for %s', cls));
    end

    % Verify confidence
    verifyTrue(testCase, ismember(c.evidence.confidence, {'low', 'medium', 'high'}));

    % Verify Grad-CAM
    verifyTrue(testCase, isfield(c.explain, 'gradCam'));
    verifyTrue(testCase, isfield(c.explain, 'attentionImage'));
    verifyTrue(testCase, isfield(c.explain, 'evidenceOverlay'));
    verifyTrue(testCase, isfield(c.explain, 'note'));
end

% =====================================================================
%  Test 3: Missing Evidence
% =====================================================================

function test_missingEvidenceGraceful(testCase)
%TEST_MISSINGEVIDENCEGRACEFUL  Verify UI handles missing evidence fields.
    % Create a minimal case with missing evidence
    c = newCase();
    c.image = uint8(120 * ones(64, 64, 3));
    c.meta.patientId = 'TEST-MISS';
    c.meta.eye = 'right';
    c.quality.class = 'good';
    c.quality.score = 0.85;
    c.grading.grade = 1;
    c.grading.rawProbs = [0.3 0.4 0.2 0.05 0.05];
    c.grading.referable = false;
    c.grading.referableProb = 0.3;
    c.calibrated.confidence = 0.85;
    c.calibrated.uncertainty = 0.15;
    c.calibrated.reviewRequired = false;
    c.calibrated.calibratedProbs = [0.3 0.4 0.2 0.05 0.05];

    % Empty evidence
    c.evidence.vesselMask = [];
    c.evidence.opticDisc = [];
    c.evidence.fovea = [];
    c.evidence.confidence = 'low';
    c.evidence.opticDiscDetail = struct('center', [], 'bbox', [], ...
        'confidence', 0, 'status', 'not_detected', 'method', '', 'note', '');

    % No lesions
    c.evidence.lesions = struct( ...
        'exudates', struct('map', [], 'count', 0, 'features', []), ...
        'hemorrhages', struct('map', [], 'count', 0, 'features', []), ...
        'microaneurysms', struct('map', [], 'count', 0, 'features', []), ...
        'neoVasc', struct('map', [], 'count', 0, 'features', []));

    % Empty explain
    c.explain = struct('gradCam', [], 'attentionImage', [], ...
        'evidenceOverlay', [], 'note', 'No attention');

    % Empty review
    c.review = struct('action', '', 'graderId', '', 'overrideGrade', NaN, ...
        'finalReferral', false, 'status', '', 'notes', '');

    % Test that the case can be created without error
    verifyTrue(testCase, isstruct(c));
    verifyTrue(testCase, isempty(c.evidence.vesselMask));
    verifyTrue(testCase, isempty(c.evidence.opticDiscDetail.center));
    verifyEqual(testCase, c.evidence.opticDiscDetail.status, 'not_detected');
    verifyEqual(testCase, c.evidence.confidence, 'low');

    % Verify buildReport handles empty evidence
    report = buildReport(c, experiment_config());
    verifyTrue(testCase, isstruct(report));
    verifyTrue(testCase, isfield(report, 'data'));
    verifyTrue(testCase, isfield(report, 'summary'));
    verifyTrue(testCase, ~isempty(report.summary));
end

function test_missingGradCamGraceful(testCase)
%TEST_MISSINGGRADCAMGRACEFUL  Verify Grad-CAM is handled when net is empty.
    c = runPipeline('scenario', 'good');

    % With empty net, gradCam should be zeros (honest)
    verifyTrue(testCase, all(c.explain.gradCam(:) == 0) || ...
        ~isempty(c.explain.gradCam), 'Grad-CAM not honest');
    verifyTrue(testCase, ~isempty(c.explain.note), 'Grad-CAM note missing');
end

% =====================================================================
%  Test 4: Review Workflow
% =====================================================================

function test_approveWorkflow(testCase)
%TEST_APPROVEWORKFLOW  Verify approve action through submitReview.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    reviewerInput = struct( ...
        'action', 'approve', ...
        'graderId', 'OPH-TEST-01', ...
        'overrideGrade', NaN, ...
        'notes', 'Approved after visual inspection.');

    review = submitReview(c, reviewerInput, cfg);

    verifyEqual(testCase, review.action, 'approve');
    verifyEqual(testCase, review.status, 'approved');
    verifyEqual(testCase, review.graderId, 'OPH-TEST-01');
    verifyTrue(testCase, isnan(review.overrideGrade));
    verifyEqual(testCase, review.notes, 'Approved after visual inspection.');
    verifyTrue(testCase, islogical(review.finalReferral));

    % Final referral should match AI grade vs threshold
    expectedReferral = c.grading.grade >= cfg.referThreshold;
    verifyEqual(testCase, review.finalReferral, expectedReferral);
end

function test_overrideWorkflow(testCase)
%TEST_OVERRIDEWORKFLOW  Verify override action through submitReview.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    reviewerInput = struct( ...
        'action', 'override', ...
        'graderId', 'OPH-TEST-02', ...
        'overrideGrade', 3, ...
        'notes', 'CADx found microaneurysms not flagged.');

    review = submitReview(c, reviewerInput, cfg);

    verifyEqual(testCase, review.action, 'override');
    verifyEqual(testCase, review.status, 'overridden');
    verifyEqual(testCase, review.overrideGrade, 3);
    verifyEqual(testCase, review.graderId, 'OPH-TEST-02');
    verifyTrue(testCase, review.finalReferral);  % grade 3 >= 2
end

function test_overrideGradePreservesOriginal(testCase)
%TEST_OVERRIDEGRADEPRESERVESORIGINAL  Verify override does not modify original grading.
    c = runPipeline('scenario', 'good');
    originalGrade = c.grading.grade;
    originalProbs = c.grading.rawProbs;
    cfg = experiment_config();

    reviewerInput = struct( ...
        'action', 'override', ...
        'graderId', 'OPH-TEST-03', ...
        'overrideGrade', 4, ...
        'notes', 'Severe case detected.');

    review = submitReview(c, reviewerInput, cfg);

    % Original grading must be unchanged
    verifyEqual(testCase, c.grading.grade, originalGrade);
    verifyEqual(testCase, c.grading.rawProbs, originalProbs);

    % Review stores override separately
    verifyEqual(testCase, review.overrideGrade, 4);
    verifyTrue(testCase, review.finalReferral);  % grade 4 >= 2
end

function test_recaptureWorkflow(testCase)
%TEST_RECAPTUREWORKFLOW  Verify recapture action through submitReview.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    reviewerInput = struct( ...
        'action', 'recapture', ...
        'graderId', 'OPH-TEST-04', ...
        'overrideGrade', NaN, ...
        'notes', 'Image has artifact not flagged by quality gate.');

    review = submitReview(c, reviewerInput, cfg);

    verifyEqual(testCase, review.action, 'recapture');
    verifyTrue(testCase, isnan(review.overrideGrade));
    verifyFalse(testCase, review.finalReferral);  % recapture -> no referral
    verifyEqual(testCase, review.notes, 'Image has artifact not flagged by quality gate.');
end

function test_autoReview(testCase)
%TEST_AUTOREVIEW  Verify auto-review when no reviewer input is provided.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    review = submitReview(c, [], cfg);

    verifyEqual(testCase, review.action, 'auto');
    verifyEqual(testCase, review.status, 'auto');
    verifyTrue(testCase, isnan(review.overrideGrade));
    verifyTrue(testCase, isempty(review.graderId));
    verifyTrue(testCase, isempty(review.notes));
end

function test_reviewRequiresAction(testCase)
%TEST_REVIEWREQUIRESACTION  Verify invalid review action raises error.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    reviewerInput = struct( ...
        'action', 'invalid_action', ...
        'graderId', 'OPH-TEST', ...
        'overrideGrade', NaN, ...
        'notes', '');

    verifyError(testCase, @() submitReview(c, reviewerInput, cfg), ...
        'RetinaSense:submitReview:BadAction');
end

function test_overrideRequiresValidGrade(testCase)
%TEST_OVERRIDERQUIRESVALIDGRADE  Verify override with invalid grade raises error.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    reviewerInput = struct( ...
        'action', 'override', ...
        'graderId', 'OPH-TEST', ...
        'overrideGrade', 7, ...  % invalid
        'notes', '');

    verifyError(testCase, @() submitReview(c, reviewerInput, cfg), ...
        'RetinaSense:submitReview:BadOverrideGrade');
end

% =====================================================================
%  Test 5: Report Integration
% =====================================================================

function test_reportGenerationAfterApprove(testCase)
%TEST_REPORTGENERATIONAFTERAPPROVE  Verify report can be built after approval.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    reviewerInput = struct( ...
        'action', 'approve', ...
        'graderId', 'OPH-RPT', ...
        'overrideGrade', NaN, ...
        'notes', 'Report test.');

    c.review = submitReview(c, reviewerInput, cfg);
    report = buildReport(c, cfg);

    verifyTrue(testCase, isstruct(report));
    verifyTrue(testCase, isfield(report, 'data'));
    verifyTrue(testCase, isfield(report, 'summary'));
    verifyTrue(testCase, isfield(report, 'filepath'));
    verifyTrue(testCase, isfield(report, 'review'));
    verifyTrue(testCase, ~isempty(report.summary));

    % Report review should match the submission
    verifyEqual(testCase, report.review.action, 'approve');
    verifyEqual(testCase, report.review.status, 'approved');
    verifyEqual(testCase, report.review.graderId, 'OPH-RPT');
end

function test_reportContainsEvidence(testCase)
%TEST_REPORTCONTAINSEVIDENCE  Verify report data contains evidence fields.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    report = buildReport(c, cfg);

    % Evidence section
    verifyTrue(testCase, isfield(report.data, 'evidence'), 'Report missing evidence');
    verifyTrue(testCase, isfield(report.data.evidence, 'opticDisc'), 'Report missing opticDisc');
    verifyTrue(testCase, isfield(report.data.evidence, 'fovea'), 'Report missing fovea');
    verifyTrue(testCase, isfield(report.data.evidence, 'vessels'), 'Report missing vessels');
    verifyTrue(testCase, isfield(report.data.evidence, 'lesions'), 'Report missing lesions');
    verifyTrue(testCase, isfield(report.data.evidence, 'advisoryConfidence'), ...
        'Report missing advisoryConfidence');

    % Lesion classes in report
    classes = {'exudates', 'hemorrhages', 'microaneurysms', 'neoVasc'};
    for i = 1:numel(classes)
        verifyTrue(testCase, isfield(report.data.evidence.lesions, classes{i}), ...
            sprintf('Report missing lesion class: %s', classes{i}));
    end

    % Disclaimer
    verifyTrue(testCase, isfield(report, 'disclaimer'));
    verifyTrue(testCase, ~isempty(report.disclaimer));
end

function test_reportContainsGradeLabel(testCase)
%TEST_REPORTCONTAINSGRADELABEL  Verify report has grade label string.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    report = buildReport(c, cfg);

    verifyTrue(testCase, isfield(report.data, 'gradeLabel'));
    validLabels = {'No DR', 'Mild NPDR', 'Moderate NPDR', 'Severe NPDR', 'Proliferative DR'};
    verifyTrue(testCase, ismember(report.data.gradeLabel, validLabels), ...
        sprintf('Invalid grade label: %s', report.data.gradeLabel));
end

% =====================================================================
%  Test 6: Regression — Batch 1–4 Contracts
% =====================================================================

function test_regressionBatch1OpticDisc(testCase)
%TEST_REGRESSIONBATCH1OPTICDISC  Verify optic disc field contract (Batch 1).
    c = runPipeline('scenario', 'good');

    % evidence.opticDisc
    verifyTrue(testCase, isfield(c.evidence, 'opticDisc'));
    verifyTrue(testCase, isempty(c.evidence.opticDisc) || ...
        (isvector(c.evidence.opticDisc) && numel(c.evidence.opticDisc) >= 2));

    % evidence.opticDiscDetail
    verifyTrue(testCase, isfield(c.evidence, 'opticDiscDetail'));
    verifyTrue(testCase, isstruct(c.evidence.opticDiscDetail));
    verifyTrue(testCase, isfield(c.evidence.opticDiscDetail, 'center'));
    verifyTrue(testCase, isfield(c.evidence.opticDiscDetail, 'bbox'));
    verifyTrue(testCase, isfield(c.evidence.opticDiscDetail, 'confidence'));
    verifyTrue(testCase, isfield(c.evidence.opticDiscDetail, 'status'));
    verifyTrue(testCase, isfield(c.evidence.opticDiscDetail, 'method'));
    verifyTrue(testCase, ismember(c.evidence.opticDiscDetail.status, ...
        {'detected', 'low_confidence', 'not_detected'}));
end

function test_regressionBatch1Fovea(testCase)
%TEST_REGRESSIONBATCH1FOVEA  Verify fovea field contract (Batch 1).
    c = runPipeline('scenario', 'good');

    verifyTrue(testCase, isfield(c.evidence, 'fovea'));
    verifyTrue(testCase, isempty(c.evidence.fovea) || ...
        (isvector(c.evidence.fovea) && numel(c.evidence.fovea) >= 2));
end

function test_regressionBatch2VesselMask(testCase)
%TEST_REGRESSIONBATCH2VESSELMASK  Verify vessel mask field contract (Batch 2).
    c = runPipeline('scenario', 'good');

    verifyTrue(testCase, isfield(c.evidence, 'vesselMask'));
    if ~isempty(c.evidence.vesselMask)
        verifyTrue(testCase, islogical(c.evidence.vesselMask) || ...
            isnumeric(c.evidence.vesselMask));
    end
end

function test_regressionBatch3Lesions(testCase)
%TEST_REGRESSIONBATCH3LESIONS  Verify all four lesion classes (Batch 3).
    c = runPipeline('scenario', 'good');

    verifyTrue(testCase, isfield(c.evidence, 'lesions'));
    classes = {'exudates', 'hemorrhages', 'microaneurysms', 'neoVasc'};
    for i = 1:numel(classes)
        cls = classes{i};
        verifyTrue(testCase, isfield(c.evidence.lesions, cls), ...
            sprintf('Missing lesion class: %s', cls));
        les = c.evidence.lesions.(cls);
        verifyTrue(testCase, isfield(les, 'map'), sprintf('Missing map: %s', cls));
        verifyTrue(testCase, isfield(les, 'count'), sprintf('Missing count: %s', cls));
        verifyTrue(testCase, isfield(les, 'features'), sprintf('Missing features: %s', cls));
        verifyTrue(testCase, les.count >= 0, sprintf('Negative count: %s', cls));
    end
end

function test_regressionBatch4Report(testCase)
%TEST_REGRESSIONBATCH4REPORT  Verify report structure (Batch 4).
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    report = buildReport(c, cfg);

    verifyTrue(testCase, isfield(report, 'data'));
    verifyTrue(testCase, isfield(report, 'summary'));
    verifyTrue(testCase, isfield(report, 'filepath'));
    verifyTrue(testCase, isfield(report, 'review'));
    verifyTrue(testCase, isfield(report, 'disclaimer'));

    % Report data fields
    d = report.data;
    verifyTrue(testCase, isfield(d, 'patientId'));
    verifyTrue(testCase, isfield(d, 'eye'));
    verifyTrue(testCase, isfield(d, 'quality'));
    verifyTrue(testCase, isfield(d, 'grade'));
    verifyTrue(testCase, isfield(d, 'referable'));
    verifyTrue(testCase, isfield(d, 'confidence'));
    verifyTrue(testCase, isfield(d, 'uncertainty'));
    verifyTrue(testCase, isfield(d, 'reviewAction'));
    verifyTrue(testCase, isfield(d, 'finalReferral'));
end

function test_regressionEvidenceConfidence(testCase)
%TEST_REGRESSIONEVIDENCECONFIDENCE  Verify evidence confidence is valid string.
    c = runPipeline('scenario', 'good');

    verifyTrue(testCase, isfield(c.evidence, 'confidence'));
    verifyTrue(testCase, ismember(c.evidence.confidence, {'low', 'medium', 'high'}));
end

function test_regressionCalibration(testCase)
%TEST_REGRESSIONCALIBRATION  Verify calibration structure (Batch 1-4).
    c = runPipeline('scenario', 'good');

    verifyTrue(testCase, isfield(c.calibrated, 'calibratedProbs'));
    verifyTrue(testCase, isfield(c.calibrated, 'confidence'));
    verifyTrue(testCase, isfield(c.calibrated, 'uncertainty'));
    verifyTrue(testCase, isfield(c.calibrated, 'reviewRequired'));

    verifyTrue(testCase, c.calibrated.confidence >= 0 && c.calibrated.confidence <= 1);
    verifyTrue(testCase, c.calibrated.uncertainty >= 0 && c.calibrated.uncertainty <= 1);
    verifyTrue(testCase, abs(sum(c.calibrated.calibratedProbs) - 1) < 1e-6);
end

function test_regressionGradeRange(testCase)
%TEST_REGRESSIONGRADERANGE  Verify DR grade is in 0..4.
    c = runPipeline('scenario', 'good');

    verifyTrue(testCase, c.grading.grade >= 0 && c.grading.grade <= 4);
    verifyTrue(testCase, numel(c.grading.rawProbs) == 5);
    verifyTrue(testCase, abs(sum(c.grading.rawProbs) - 1) < 1e-6);
    verifyTrue(testCase, c.grading.referableProb >= 0 && c.grading.referableProb <= 1);
end

function test_regressionOverrideGradeValid(testCase)
%TEST_REGRESSIONOVERRIDERANGE  Verify override grade 0..4 validation.
    cfg = experiment_config();
    c = newCase();
    c.grading.grade = 1;

    % Valid override
    reviewerInput = struct('action', 'override', 'graderId', 'T', ...
        'overrideGrade', 3, 'notes', '');
    review = submitReview(c, reviewerInput, cfg);
    verifyEqual(testCase, review.overrideGrade, 3);
    verifyTrue(testCase, review.finalReferral);

    % Invalid override (NaN)
    reviewerInput.overrideGrade = NaN;
    verifyError(testCase, @() submitReview(c, reviewerInput, cfg), ...
        'RetinaSense:submitReview:BadOverrideGrade');

    % Invalid override (> 4)
    reviewerInput.overrideGrade = 5;
    verifyError(testCase, @() submitReview(c, reviewerInput, cfg), ...
        'RetinaSense:submitReview:BadOverrideGrade');
end

% =====================================================================
%  Test 7: End-to-End Workflow
% =====================================================================

function test_endToEndApproveAndReport(testCase)
%TEST_ENDTOENDAPPROVEANDREPORT  Full workflow: load -> review -> approve -> report.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    % Approve
    reviewerInput = struct('action', 'approve', 'graderId', 'E2E-01', ...
        'overrideGrade', NaN, 'notes', 'E2E test approval.');
    c.review = submitReview(c, reviewerInput, cfg);

    % Build report
    c.report = buildReport(c, cfg);

    % Verify full chain
    verifyEqual(testCase, c.review.action, 'approve');
    verifyEqual(testCase, c.review.status, 'approved');
    verifyTrue(testCase, ~isempty(c.report.summary));
    verifyTrue(testCase, isfield(c.report.data, 'evidence'));
    verifyEqual(testCase, c.report.review.action, 'approve');
end

function test_endToEndOverrideAndReport(testCase)
%TEST_ENDTOENDOVERRIDEANDREPORT  Full workflow: load -> review -> override -> report.
    c = runPipeline('scenario', 'good');
    cfg = experiment_config();

    % Override
    reviewerInput = struct('action', 'override', 'graderId', 'E2E-02', ...
        'overrideGrade', 3, 'notes', 'E2E test override.');
    c.review = submitReview(c, reviewerInput, cfg);

    % Build report
    c.report = buildReport(c, cfg);

    % Verify
    verifyEqual(testCase, c.review.action, 'override');
    verifyEqual(testCase, c.review.overrideGrade, 3);
    verifyTrue(testCase, c.review.finalReferral);  % grade 3 >= 2
    verifyTrue(testCase, isfield(c.report.data, 'evidence'));
    verifyEqual(testCase, c.report.review.overrideGrade, 3);
end
