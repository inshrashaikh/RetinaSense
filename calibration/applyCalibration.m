function cal = applyCalibration(grading, T, params)
%APPLYCALIBRATION  Stage 8b: temperature-scaled confidence + uncertainty.
%
%   cal = applyCalibration(grading, T, params)
%   (implements the §4.6 'calibrateOutput(grading, T, params)' contract)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.6):
%     cal.calibratedProbs 1x5 double (temperature-scaled, sums to 1)
%     cal.confidence       double 0..1  = max(calibratedProbs)
%     cal.uncertainty      double 0..1  = normalized entropy of calibratedProbs
%     cal.reviewRequired   logical      = confidence<confLow | uncertainty>uncHigh | forced
%
%   RetinaSense refuses to treat raw softmax as calibrated certainty (§3.7/FR-08).
%   In Sprint 0, with no trained model, T=1 (identity): calibrated = raw probs of
%   the mock grading. The entropy math here is real and tested.
%
%   TODO(Sprint 3): use T fit by fitTemperature on real validation logits.

    cfg = experiment_config();
    if nargin < 2 || isempty(T); T = cfg.calibration.temperature; end
    if nargin < 3; params = cfg.calibration; end

    probs = grading.rawProbs(:)';
    if abs(sum(probs) - 1) > 1e-6
        raiseError('applyCalibration', 'InvalidProbs', 'rawProbs must sum to 1.');
    end

    % Temperature-scaled softmax.
    logits = log(max(probs, eps));
    z = (logits - max(logits)) / T;
    calibratedProbs = exp(z) / sum(exp(z));

    confidence  = max(calibratedProbs);
    uncertainty = normalizedEntropy(calibratedProbs);

    reviewRequired = confidence < params.confidenceLow || ...
                     uncertainty > params.uncertaintyHigh || ...
                     cfg.review.alwaysReview;

    cal = struct( ...
        'calibratedProbs', calibratedProbs, ...
        'confidence',      confidence, ...
        'uncertainty',     uncertainty, ...
        'reviewRequired',  reviewRequired);
end

function h = normalizedEntropy(p)
    % Normalized Shannon entropy over the 5 classes, 0..1.
    p = p(:)';
    h = -sum(p .* log(max(p, eps))) / log(5);
    h = max(0, min(1, h));
end