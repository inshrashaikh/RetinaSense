function tests = test_pipeline
%TEST_PIPELINE  Orchestration tests for scripts/runPipeline.m.
    tests = functiontests(localfunctions);
end

function test_goodCaseRunsEndToEnd(testCase)
    c = runPipeline('scenario', 'good');
    verifyEqual(testCase, c.quality.class, 'good');
    verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'grading')));
    verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'calibration')));
    verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'report')));
    verifyTrue(testCase, ~isempty(c.pipeline.finishedAt));
    verifyTrue(testCase, isempty(c.pipeline.exitStage));
    verifyEqual(testCase, class(c.grading.grade), 'double');
    verifyTrue(testCase, ismember(c.review.status, {'auto','approved','reqReview'}));
end

function test_ungradableExitsAtGate(testCase)
    c = runPipeline('scenario', 'ungradable');
    verifyEqual(testCase, c.quality.class, 'ungradable');
    verifyEqual(testCase, c.pipeline.exitStage, 'qualityGate');
    verifyTrue(testCase, ~any(strcmp(c.pipeline.stages, 'grading')));
    verifyTrue(testCase, ~isempty(c.quality.recapture.reasonCode));
end

function test_borderlineRunsEnhancementThenProceeds(testCase)
    c = runPipeline('scenario', 'borderline');
    % The borderline branch is taken. On success c.quality is REPLACED by the
    % post-enhancement recheck ('good') and the pipeline runs to the report;
    % on failure the pipeline exits at the post-enhancement recheck.
    if c.pipeline.enhanced
        verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'enhancement')));
        verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'grading')));
        verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'report')));
    else
        verifyEqual(testCase, c.pipeline.exitStage, 'enhancementRecheck');
    end
end

function test_reviewerOverridePropagates(testCase)
    c = runPipeline('scenario', 'good', ...
        struct('action','override','graderId','OPH-9','overrideGrade',3,'notes','x'));
    verifyEqual(testCase, c.review.status, 'overridden');
    verifyEqual(testCase, c.review.overrideGrade, 3);
    verifyTrue(testCase, c.review.finalReferral);
    verifyTrue(testCase, c.report.review.finalReferral);
end

function test_caseContinueMode(testCase)
    c0 = runPipeline('scenario', 'good');
    verifyTrue(testCase, ~isempty(c0.image));
    % continue-mode: feed the prior case back in; pipeline re-runs on the
    % same working image and completes.
    c1 = runPipeline(c0);
    verifyTrue(testCase, ~isempty(c1.image));
    verifyTrue(testCase, any(strcmp(c1.pipeline.stages, 'report')));
end

function test_mockDisabledWithoutModelErrors(testCase)
% With mock disabled and no trained model the pipeline must refuse before any
% grading (MissingModel gate). When a benchmark-recorded model IS available the
% gate legitimately does not fire, so the guard is asserted only on a system
% without one (mirrors testStopsWhenToolboxMissing skip pattern).
    if experiment_config().model.available
        warning('test_pipeline:skip', ...
            'Benchmark-recorded model present; skipping MissingModel gate test.');
        return;
    end
    verifyError(testCase, @() runPipeline('scenario', 'good', 'mock', false), ...
        'RetinaSense:runPipeline:MissingModel');
end