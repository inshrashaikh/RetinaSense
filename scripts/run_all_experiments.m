function run_all_experiments()
%RUN_ALL_EXPERIMENTS  Aggregate training + evaluation + ablatventory driver.
%
%   TODO(Sprint 8+): orchestrates prepareClassifierData -> benchmark_backbones
%   -> trainClassifier -> evaluateClassifier -> runValidation -> runAblation
%   -> external Messidor-2, with fixed seed config for reproducibility.
%
%   Sprint 0: clearly refuses to run (no training happens before Sprint 2).
%   Do NOT run silently and pretend experiments happened.

    raiseError('run_all_experiments', 'NotImplemented', ...
        'Experiments start at Sprint 2. Nothing has been trained or evaluated.');
end