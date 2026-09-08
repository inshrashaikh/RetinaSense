function results = runValidation(net, calibT)
%RUNVALIDATION  Full hold-out validation of the DR pipeline.
%
%   results = runValidation(net, calibT)
%
%   TODO(Sprint 8): confusion matrix, ROC/AUC, referable SE/SP (target >90%/>85%),
%   ECE + reliability, kappa, per-level breakdown — via evaluation/metrics.m.
%   Messidor-2 is never part of training/hyperparams; external validation only
%   (docs/ARCHITECTURE.md §8).
%
%   Sprint 0: refuses to fabricate validation results.

    raiseError('runValidation', 'NotImplemented', ...
        'Validation runs at Sprint 8 with a real trained model. No fake metrics.');
end