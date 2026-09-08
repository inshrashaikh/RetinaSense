function T = fitTemperature(validationLogits, validationLabels, initT)
%FITTEMPERATURE  Stage 8a: temperature scaling fit (on validation logits only).
%
%   T = fitTemperature(validationLogits, validationLabels, initT)
%
%   Single-parameter temperature scaling: T > 1 => softer probs. Fit by
%   minimizing NLL on the VALIDATION split. A single scalar makes it robust.
%   (docs/ARCHITECTURE.md §3.7.)
%
%   TODO(Sprint 3): implement with fminsearch / Statistics & ML.
%   Sprint 0: refuses to fake a calibration; needs real validation logits.

    if nargin < 3; initT = 1.0; end
    raiseError('fitTemperature', 'NotImplemented', ...
        'Temperature fitting is a Sprint 3+ task (requires real validation logits).');
end