function tests = test_module_interfaces
%TEST_MODULE_INTERFACES  Contract tests for the §4 module interfaces (mock).
    tests = functiontests(localfunctions);
end

function test_ingestImageSynthetic(testCase)
    meta = struct('patientId','P1','eye','right','timestamp','2026-01-01T00:00:00','phcId','PHC-X');
    c = ingestImage(meta, '');
    verifyEqual(testCase, class(c.image), 'uint8');
    verifyEqual(testCase, size(c.image, 3), 3);
    verifyTrue(testCase, max(size(c.image, 1), size(c.image, 2)) <= 1024);
    verifyEqual(testCase, c.meta.patientId, 'P1');
end

function test_ingestImageFromFile(testCase)
    meta = struct('patientId','P2','eye','left','timestamp','2026-01-01T00:00:00','phcId','PHC-X');
    asset = fullfile(paths().assets, 'synthetic_fundus_demo.png');
    c = ingestImage(meta, asset);
    verifyEqual(testCase, size(c.image, 3), 3);
    verifyTrue(testCase, ~isempty(c.image));
end

function test_ingestImageMissingFileRaises(testCase)
    meta = struct('patientId','P3','eye','left','timestamp','','phcId','');
    verifyError(testCase, @() ingestImage(meta, 'does_not_exist.png'), ...
        'RetinaSense:ingestImage:FileNotFound');
end

function test_assessQualityContract(testCase)
    c = ingestImage(struct('patientId','P','eye','right','timestamp','','phcId',''), '');
    q = assessQuality(c.image, quality_thresholds());
    verifyTrue(testCase, ismember(q.class, {'good','borderline','ungradable'}));
    verifyTrue(testCase, q.score >= 0 && q.score <= 1);
    verifyTrue(testCase, isfield(q.metrics, 'focus'));
    verifyTrue(testCase, iscell(q.failureReasons));
    verifyTrue(testCase, isfield(q.recapture, 'reasonCode'));
end

function test_ungradableRecapture(testCase)
    % Near-black image must fail the gate and produce recapture guidance.
    img = uint8(zeros(128, 128, 3) + 8);
    q = assessQuality(img, quality_thresholds());
    verifyEqual(testCase, q.class, 'ungradable');
    verifyTrue(testCase, ~isempty(q.recapture.reasonCode));
    verifyTrue(testCase, ismember(q.recapture.reasonCode, ...
        {'REFOCUS','FIX_LIGHTING','RECENTER_FOV','CLEAR_ARTIFACTS'}));
end

function test_recaptureFeedbackCodes(testCase)
    r = recaptureFeedback({'focus'});
    verifyEqual(testCase, r.reasonCode, 'REFOCUS');
    r2 = recaptureFeedback({});
    verifyEqual(testCase, r2.reasonCode, '');
end

function test_enhanceImageSizePreserved(testCase)
    img = uint8(120 * ones(96, 96, 3));
    q = assessQuality(img, quality_thresholds());
    [enh, meta] = enhanceImage(img, q, preprocess_config().enhance);
    verifyEqual(testCase, size(enh), size(img));
    verifyTrue(testCase, iscell(meta.appliedOps));
    verifyTrue(testCase, isfield(meta, 'recheckClass'));
    verifyTrue(testCase, isfield(meta, 'improved'));
end

function test_recheckQualityAdoptsEnhanced(testCase)
    img = uint8(120 * ones(96, 96, 3));
    q = assessQuality(img, quality_thresholds());
    [enh, meta] = enhanceImage(img, q, preprocess_config().enhance);
    [ok, rq, meta] = recheckQuality(enh, meta, q.score);
    verifyTrue(testCase, islogical(ok));
    verifyTrue(testCase, ismember(rq.class, {'good','borderline','ungradable'}));
    verifyEqual(testCase, meta.recheckClass, rq.class);
end

function test_analyzeRetinaAdvisoryContract(testCase)
    img = uint8(120 * ones(96, 96, 3));
    ev = analyzeRetina(img, [], struct());
    verifyTrue(testCase, isfield(ev, 'vesselMask'));
    verifyTrue(testCase, isfield(ev, 'opticDisc'));
    verifyTrue(testCase, isfield(ev, 'fovea'));
    verifyTrue(testCase, isfield(ev, 'lesions'));
    verifyTrue(testCase, isfield(ev, 'confidence'));
    verifyTrue(testCase, isfield(ev, 'opticDiscDetail'));
    verifyTrue(testCase, ismember(ev.confidence, {'low','medium','high'}));
    verifyEqual(testCase, size(ev.vesselMask), size(img(:,:,1)));
    % opticDiscDetail contract
    verifyTrue(testCase, isstruct(ev.opticDiscDetail));
    verifyTrue(testCase, isfield(ev.opticDiscDetail, 'center'));
    verifyTrue(testCase, isfield(ev.opticDiscDetail, 'status'));
    verifyTrue(testCase, ismember(ev.opticDiscDetail.status, {'detected','low_confidence','not_detected'}));
end

function test_classifyImageContract(testCase)
    img = uint8(120 * ones(96, 96, 3));
    g = classifyImage(img, [], classification_config());
    verifyEqual(testCase, size(g.rawProbs), [1 5]);
    verifyTrue(testCase, abs(sum(g.rawProbs) - 1) < 1e-9);
    verifyTrue(testCase, g.grade >= 0 && g.grade <= 4);
    verifyTrue(testCase, g.referableProb >= 0 && g.referableProb <= 1);
    verifyTrue(testCase, islogical(g.referable));
end

function test_computeGradCAMHonest(testCase)
    img = uint8(120 * ones(96, 96, 3));
    x = computeGradCAM(img, [], [], struct('lesions', struct()), experiment_config().explainability);
    verifyTrue(testCase, all(x.gradCam(:) == 0));   % no fake attention
    verifyEqual(testCase, max(size(x.gradCam, 1), size(x.gradCam, 2)), ...
        max(size(img, 1), size(img, 2)));
    verifyTrue(testCase, ischar(x.note) && ~isempty(x.note));
end

function test_applyCalibrationMath(testCase)
    g.grade = 3; g.referableProb = 0.9; g.referable = true;
    g.rawProbs = [0.02 0.04 0.10 0.80 0.04];
    cal = applyCalibration(g, 1.0, experiment_config().calibration);
    verifyEqual(testCase, size(cal.calibratedProbs), [1 5]);
    verifyTrue(testCase, abs(sum(cal.calibratedProbs) - 1) < 1e-9);
    verifyEqual(testCase, cal.confidence, 0.8, 'AbsTol', 1e-9);
    verifyTrue(testCase, cal.uncertainty >= 0 && cal.uncertainty <= 1);
end

function test_submitReviewVariants(testCase)
    c = newCase();
    c.grading.grade = 1;
    cfg = experiment_config();

    r1 = submitReview(c, [], cfg);
    verifyEqual(testCase, r1.status, 'auto');
    verifyTrue(testCase, ~r1.finalReferral);  % grade 1 < 2

    r2 = submitReview(c, struct('action','approve','graderId','O1', ...
        'overrideGrade', NaN, 'notes',''), cfg);
    verifyEqual(testCase, r2.status, 'approved');

    r3 = submitReview(c, struct('action','override','graderId','O2', ...
        'overrideGrade', 3, 'notes','found RDs'), cfg);
    verifyEqual(testCase, r3.status, 'overridden');
    verifyTrue(testCase, r3.finalReferral);   % override grade 3 >= 2
end

function test_buildReportContract(testCase)
    c = newCase();
    c.meta.patientId = 'P9';
    c.quality.class = 'good';
    c.grading.grade = 2; c.grading.referable = true;
    c.calibrated.confidence = 0.93; c.calibrated.uncertainty = 0.05;
    c.review.action = 'auto'; c.review.finalReferral = true;
    rep = buildReport(c, experiment_config());
    verifyTrue(testCase, isfield(rep, 'data'));
    verifyTrue(testCase, isfield(rep, 'summary'));
    verifyTrue(testCase, isfield(rep, 'filepath'));
    verifyTrue(testCase, isfield(rep, 'review'));
    verifyTrue(testCase, ~isempty(rep.summary));
end

function test_metricsRealMath(testCase)
    labels = [0 0 0 1 1 2 2 3 3 4]';
    preds  = [0 0 0 1 1 2 2 3 4 4]';
    probs  = repmat(0.2, 10, 5);
    m = metrics(labels, preds, probs);
    verifyTrue(testCase, m.accuracy > 0);
    verifyTrue(testCase, m.referableSensitivity >= 0 && m.referableSensitivity <= 1);
    verifyTrue(testCase, m.referableSpecificity >= 0 && m.referableSpecificity <= 1);
    verifyTrue(testCase, ~isnan(m.quadraticKappa));
    verifyTrue(testCase, m.ece >= 0 && m.ece <= 1);
end