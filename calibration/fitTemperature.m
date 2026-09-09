function T = fitTemperature(validationLogits, validationLabels, initT)
%FITTEMPERATURE  Stage 8a: temperature-scaling fit on VALIDATION logits only.
%
%   T = fitTemperature(validationLogits, validationLabels, initT)
%
%   validationLogits: NxK network logits (PRE-softmax) from the validation split
%   validationLabels: Nx1 integer grades 0..4 for those examples
%   initT:            scalar starting temperature (default 1.0)
%
%   Returns T > 0 minimizing the negative log-likelihood of the validation set:
%       T* = argmin_T  -Σ_n log softmax(z_n / T)_{y_n}
%
%   Temperature scaling is the single-parameter, deliberately simple, robust
%   calibration method (docs/ARCHITECTURE.md §3.7). T>1 softens probabilities.
%
%   HONESTY (AGENTS.md): this function requires REAL validation logits. With no
%   logits supplied it raises a clear error; it never returns a fabricated T.
%   Validation-only: the test/external splits are never used to fit T.

    if nargin < 3 || isempty(initT); initT = 1.0; end
    if nargin < 2 || isempty(validationLogits) || isempty(validationLabels)
        raiseError('fitTemperature', 'NoLogits', ...
            'fitTemperature needs real validation logits + labels (from a trained net).');
    end

    logits = validationLogits;
    y      = validationLabels(:) + 1;   % 0..4 -> 1..5 indexing
    if size(logits, 1) ~= numel(y)
        raiseError('fitTemperature', 'ShapeMismatch', ...
            'logits rows (%d) must match labels (%d).', size(logits,1), numel(y));
    end

    % Fit in log-space so T stays strictly positive for fminsearch.
    f = @(logT) nll(logits, y, exp(logT));
    logTstar = fminsearch(f, log(initT), optimset('TolX', 1e-6, 'MaxFunEvals', 200));
    T = exp(logTstar);

    if ~isfinite(T) || T <= 0
        raiseError('fitTemperature', 'BadFit', 'Temperature fit failed (T=%.3f).', T);
    end
end

function v = nll(logits, y, T)
%NLL  Mean negative log-likelihood of labels under softmax(logits/T).
    z   = logits ./ T;
    z   = z - max(z, [], 2);                       % shift for numerical stability
    lse = log(sum(exp(z), 2));
    v   = mean(-z(sub2ind(size(z), (1:size(z,1))', y)) + lse);
end