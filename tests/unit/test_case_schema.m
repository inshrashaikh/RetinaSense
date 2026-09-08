function tests = test_case_schema
%TEST_CASE_SCHEMA  Unit tests for the shared Case structure (newCase.m).
    tests = functiontests(localfunctions);
end

function test_newCaseHasAllContractFields(testCase)
    c = newCase();
    required = {'image','imagePath','meta','quality','enhancement','evidence', ...
                'grading','explain','calibrated','review','report','pipeline','model'};
    for i = 1:numel(required)
        verifyTrue(testCase, isfield(c, required{i}), ...
            sprintf('Case missing required field: %s', required{i}));
    end
end

function test_qualitySchema(testCase)
    c = newCase();
    verifyTrue(testCase, isfield(c.quality, 'score'));
    verifyTrue(testCase, isfield(c.quality, 'class'));
    verifyTrue(testCase, isfield(c.quality, 'metrics'));
    verifyEqual(testCase, fieldnames(c.quality.metrics)', {'focus';'illumination';'fovCoverage';'artifacts'}');
    verifyTrue(testCase, isfield(c.quality, 'failureReasons'));
    verifyTrue(testCase, isfield(c.quality, 'recapture'));
end

function test_gradingSchema(testCase)
    c = newCase();
    verifyEqual(testCase, size(c.grading.rawProbs), [1 5]);
    verifyTrue(testCase, isnan(c.grading.grade));
end

function test_lesionsSchema(testCase)
    c = newCase();
    verifyEqual(testCase, fieldnames(c.evidence.lesions)', ...
        {'exudates';'hemorrhages';'microaneurysms';'neoVasc'}');
    for i = 1:4
        cls = fieldnames(c.evidence.lesions);
        les = c.evidence.lesions.(cls{i});
        verifyTrue(testCase, isfield(les, 'map'));
        verifyTrue(testCase, isfield(les, 'count'));
        verifyTrue(testCase, isfield(les, 'features'));
    end
end

function test_calibratedAndReviewSchema(testCase)
    c = newCase();
    verifyEqual(testCase, size(c.calibrated.calibratedProbs), [1 5]);
    verifyTrue(testCase, isfield(c.review, 'action'));
    verifyTrue(testCase, isfield(c.review, 'finalReferral'));
end