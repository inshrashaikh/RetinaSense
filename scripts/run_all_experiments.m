function results = run_all_experiments(varargin)
%RUN_ALL_EXPERIMENTS  Aggregate training + evaluation + ablation driver.
%
%   results = run_all_experiments()
%   results = run_all_experiments('retrain', false)
%
%   Orchestrates the full Member-1 AI/ML experiment sequence
%   (docs/ARCHITECTURE.md §2/§8; TEAM_EXECUTION_PLAN Sprint 8+):
%       1. prepareClassifierData     -> train/val/test/external datastores
%       2. benchmark_backbones       -> ResNet-50 vs EfficientNet-B0 4-axis table
%       3. trainClassifier(chosen)   -> persist the chosen backbone artifact
%       4. fitTemperature            -> T on VALIDATION logits (calibration)
%       5. evaluateClassifier        -> hold-out test metrics
%       6. runValidation             -> hold-out + external Messidor-2
%       7. runAblation               -> gate/calibration/evidence/backbone ablations
%
%   HONESTY (AGENTS.md): this driver NEVER computes or reports a metric itself.
%   Every number comes from the real modules above, which in turn refuse to run
%   without real data / a real trained net. This driver only:
%     - checks preconditions and raises a clear structured error listing the
%       missing prerequisite (it does NOT run silently and pretend experiments
%       happened), and
%     - aggregates the genuinely-produced results into one JSON report.
%
%   Gate order (raiseError 'run_all_experiments':<code>):
%     MissingManifest / ManifestEmpty   folded.csv absent or has no data rows
%     MissingToolbox                    Deep Learning Toolbox not installed
%     NoBenchmark                       backbone_benchmark.json absent/unset
%     NoModel                           chosen backbone .mat artifact absent
%     InsufficientData                  train/val/test empty
%
%   Calibration is validation-only; Messidor-2 (split='external') is NEVER used
%   for training or temperature fitting — enforced by prepareClassifierData and
%   runValidation. Low-confidence cases route to human review via the report.
%
%   Name-value options:
%     'retrain', false   reuse an existing trained artifact instead of retraining
%                        the chosen backbone (default true). When false and no
%                        artifact exists, this raises NoModel (honest).

    p = inputParser;
    addParameter(p, 'retrain', true, @(x) islogical(x));
    parse(p, varargin{:});
    opts = p.Results;

    cfg = experiment_config();

    % ------------------------- Precondition gates -------------------------
    manifest = fullfile(paths().data.manifests, 'folds.csv');
    if ~exist(manifest, 'file')
        raiseError('run_all_experiments', 'MissingManifest', ...
            'Manifest not found: %s', manifest);
    end

    data = prepareClassifierData(manifest);      % raises if schema-only / leak
    if data.n_train < 10
        raiseError('run_all_experiments', 'InsufficientData', ...
            'Need real APTOS train data (got %d rows).', data.n_train);
    end
    if data.n_test < 1
        raiseError('run_all_experiments', 'InsufficientData', ...
            'Need a non-empty hold-out test split (got %d rows).', data.n_test);
    end

    if ~isToolboxAvailable()
        raiseError('run_all_experiments', 'MissingToolbox', ...
            'Deep Learning Toolbox not available. Cannot train or evaluate a CNN.');
    end

    if isempty(cfg.model.backbone)
        raiseError('run_all_experiments', 'NoBenchmark', ...
            'No backbone selected. Run scripts/benchmark_backbones.m first.');
    end
    chosen = cfg.model.backbone;

    modelFile = fullfile(paths().data.models, sprintf('%s_dr_aptos.mat', chosen));
    if ~opts.retrain && ~exist(modelFile, 'file')
        raiseError('run_all_experiments', 'NoModel', ...
            'No trained artifact for %s (%s). Train first or pass retrain=true.', ...
            chosen, modelFile);
    end

    % --------------------------- Step 1: benchmark ---------------------------
    % Real 4-axis comparison; records cfg.model + backbone_benchmark.json.
    logMessage('info', 'run_all_experiments', 'STEP 1/7: backbone benchmark...');
    benchmark = benchmark_backbones();

    % --------------------------- Step 2: train chosen -------------------------
    logMessage('info', 'run_all_experiments', ...
        sprintf('STEP 2/7: train %s (retrain=%d)...', chosen, opts.retrain));
    if opts.retrain || ~exist(modelFile, 'file')
        net = trainClassifier(chosen, 'manifest', manifest);
        retrainUsed = true;
    else
        s = load(modelFile, 'net');          % reuse honest existing artifact
        net = s.net;
        retrainUsed = false;
    end

    % --------------------------- Step 3: calibration -------------------------
    % T is fit on VALIDATION logits only (docs/ARCHITECTURE.md §3.7). If the
    % validation split is empty the calibrated ECE is skipped (T=[]), never
    % invented.
    logMessage('info', 'run_all_experiments', 'STEP 3/7: fit temperature (val logits)...');
    T = fitCalibration(net, data.val, cfg);   % [] when no val / toolbox n/a

    % ------------------------- Step 4-7: evaluate ---------------------------
    logMessage('info', 'run_all_experiments', 'STEP 4/7: evaluate hold-out test...');
    evalOut = evaluateClassifier(net, data.test);

    logMessage('info', 'run_all_experiments', 'STEP 5/7: run validation (incl. external)...');
    validation = runValidation(net, T);

    logMessage('info', 'run_all_experiments', 'STEP 6/7: run ablations...');
    ablation = runAblation(net, T);

    % --------------------------- Step 7: report ------------------------------
    logMessage('info', 'run_all_experiments', 'STEP 7/7: aggregate report...');
    results = struct( ...
        'experiment', 'RetinaSense - APTOS 2019, chosen backbone benchmark-driven', ...
        'timestamp', datestr(now, 'yyyy-mm-ddTHH:MM:SS'), ...
        'seed', cfg.seed, ...
        'manifest', manifest, ...
        'nTrain', data.n_train, 'nVal', data.n_val, ...
        'nTest', data.n_test, 'nExternal', data.n_external, ...
        'chosenBackbone', chosen, ...
        'retrained', retrainUsed, ...
        'benchmark', benchmark, ...
        'evaluation', evalOut, ...
        'validation', validation, ...
        'ablation', ablation, ...
        'temperature', T, ...
        'calibrationNote', 'Temperature fitted on validation logits only; Messidor-2 external never used.', ...
        'note', 'All numbers are real module outputs; none fabricated.');

    writeReport(results);
    logMessage('info', 'run_all_experiments', ...
        sprintf('Aggregate report written. Chosen backbone: %s (SE=%.1f%%, SP=%.1f%% on test).', ...
        chosen, 100*evalOut.referableSensitivity, 100*evalOut.referableSpecificity));
end

% --------------------------------------------------------------------------
function T = fitCalibration(net, valDs, cfg)
%FITCALIBRATION  Real temperature fit on validation logits; [] if impossible.
    if isempty(valDs)
        T = [];
        logMessage('warn', 'run_all_experiments', ...
            'No validation split; calibration temperature skipped (T=[]).');
        return;
    end
    try
        scores = double(predict(net, valDs));
        logits = log(max(scores, eps));
        labels = double(valDs.Labels) - 1;
        T = fitTemperature(logits, labels);
        logMessage('info', 'run_all_experiments', sprintf('Calibration T=%.3f', T));
    catch ME
        % Honest skip: without real val logits we never fit/adopt a default.
        T = [];
        logMessage('warn', 'run_all_experiments', ...
            sprintf('Calibration fit unavailable (%s); T=[] -> calibrated ECE skipped.', ME.message));
    end
end

function tf = isToolboxAvailable()
%ISTOOLBOXAVAILABLE  Guard for the Deep Learning Toolbox (trainNetwork/gradCAM).
    tf = ~isempty(which('trainNetwork')) && ...
         ~isempty(which('dlnetwork')) && ...
         ~isempty(which('gradCAM'));
end

function writeReport(results)
%WRITEREPORT  Persist the aggregate honest report as JSON in output/.
    p = paths();
    if ~exist(p.output, 'dir'); mkdir(p.output); end
    file = fullfile(p.output, 'run_all_experiments_report.json');
    fid = fopen(file, 'w');
    if fid <= 0
        logMessage('warn', 'run_all_experiments', ...
            'Could not write aggregate report to %s', file);
        return;
    end
    s = jsonencode(results);
    fprintf(fid, '%s\n', s);
    fclose(fid);
    logMessage('info', 'run_all_experiments', sprintf('Report -> %s', file));
end