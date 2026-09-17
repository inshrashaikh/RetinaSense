function results = run_simulink_scenarios(scenariosToRun)
%RUN_SIMULINK_SCENARIOS  Drive DRTelemedicine.slx what-if scenarios.
%
%   results = run_simulink_scenarios()
%   results = run_simulink_scenarios(scenariosToRun)
%
%   Runs district-scale what-if scenarios (docs/ARCHITECTURE.md §7):
%     - load: baseline (~274 pts/day), low_load, high_load
%     - bandwidth: rural_1mbps, baseline (2 Mbps), rural_4mbps
%     - reviewers: solo_reviewer (1), baseline (2), team_5_reviewers (5)
%
%   Uses scenario_params.m as the single source of truth for scenario
%   parameters. If Simulink/SimEvents or DRTelemedicine.slx is unavailable,
%   validates scenario construction honestly and returns executionStatus
%   as 'PENDING' without fabricating numerical outputs.
%
%   KPI Data Sources (honest labeling):
%     MEASURED from simulation:
%       - completedPatients, throughput (patients/day), annualCapacity
%       - averageWaitingTime, queueLength, reviewerUtilization
%         Read directly from REAL SimEvents block statistics (Acquisition
%         Queue AverageWait/AverageQueueLength, Review Server Utilization,
%         Completed Sink NumberEntitiesArrived). The statistics are enabled
%         POST-BUILD (instrument_for_kpis.m) as passive listeners - enabling
%         them during build would alter entity structure and break the Input
%         Switch merges (R2026a), so the checked-in model stays clean and
%         instrumentation provably does not perturb throughput.
%     ANALYTICAL ESTIMATES from model parameters (M/M/1 approximations):
%       - meanWaitingTime, maxWaitingTime
%       - acqUtilization, networkUtilization, aiUtilization, revUtilization
%       - bottleneck (highest utilization resource)
%
%   Outputs:
%     results - 1xN struct array with fields:
%       scenario, bandwidthMbps, numReviewers, patientsPerDay,
%       throughput (MEASURED), completedPatients (MEASURED),
%       annualCapacity (MEASURED),
%       averageWaitingTime (MEASURED), queueLength (MEASURED),
%       reviewerUtilization (MEASURED),
%       meanWaitingTime (ANALYTICAL), maxWaitingTime (ANALYTICAL),
%       acqUtilization (ANALYTICAL), aiUtilization (ANALYTICAL),
%       revUtilization (ANALYTICAL), networkUtilization (ANALYTICAL),
%       bottleneck (ANALYTICAL),
%       executionStatus

    if nargin < 1 || isempty(scenariosToRun)
        scenariosToRun = {'baseline', 'low_load', 'high_load', ...
                          'rural_1mbps', 'rural_4mbps', ...
                          'solo_reviewer', 'team_5_reviewers'};
    end

    if ischar(scenariosToRun) || isstring(scenariosToRun)
        scenariosToRun = cellstr(scenariosToRun);
    end
    if ~iscell(scenariosToRun)
        fail('InvalidInput', 'scenariosToRun must be a cell array of scenario names.');
    end

    % 1. Check environment & model availability
    env = check_environment();

    if ~env.isExecutable
        log_msg('warn', sprintf(...
            'Simulink execution unavailable (%s). Validating configurations and marking executionStatus as PENDING.', ...
            env.statusReason));
    end

    % 2. Process scenarios
    nScenarios = numel(scenariosToRun);
    results = repmat(empty_result_struct(), 1, nScenarios);

    for i = 1:nScenarios
        sc = scenariosToRun{i};
        if ~ischar(sc) && ~isstring(sc)
            fail('InvalidScenarioType', 'Scenario name at index %d must be char or string.', i);
        end
        sc = char(sc);

        % Load and validate parameters from scenario_params.m
        try
            p = scenario_params(sc);
        catch ME
            log_msg('error', sprintf('Failed to load parameters for scenario "%s": %s', sc, ME.message));
            rethrow(ME);
        end

        % Execute simulation if runtime is available, else record PENDING
        if env.isExecutable
            results(i) = simulate_scenario(p, sc, env.modelPath);
        else
            results(i) = pending_scenario(p, sc);
        end
    end

    % 3. Print readable comparison table and detailed KPI report
    print_results_table(results);
    print_kpi_report(results);

    % 4. Persist the real (non-fabricated) results to JSON for the audit trail
    persist_results_json(results);

    % 5. Close the (instrumented, therefore dirty) model cleanly so the exit
    %    does not warn about unsaved changes; instrumentation is by design a
    %    runtime-only modification and the committed .slx stays flow-only.
    if env.isExecutable && bdIsLoaded('DRTelemedicine')
        close_system('DRTelemedicine', 0);
    end
end

% -------------------------------------------------------------------------
% Simulation execution helper
% -------------------------------------------------------------------------
function res = simulate_scenario(p, sc, modelPath)
    res = init_result_struct(sc, p);
    try
        load_system(modelPath);
        [~, modelName] = fileparts(modelPath);

        % Assign parameters to base workspace for Simulink model references
        assignin('base', 'params', p);

        % Reproducibility: seed the global stream the same way for every
        % scenario run (arrival draws, gate draws, service-time draws).
        rng(p.seed);

        % Runtime KPI instrumentation (post-build, passive stat listeners):
        % enables buffet stats that MUST NOT be enabled during build (they
        % would change entity structure and break the Input Switch merges).
        instrument_for_kpis(modelName);

        simOut = sim(modelName, 'StopTime', num2str(p.simTimeMin * 60));

        if ~isempty(simOut)
            % MEASURED sink counts (To Workspace, one per counter)
            kpi = measured_kpis(simOut, p);
            res.completedPatients    = kpi.completed;
            res.averageWaitingTime   = kpi.averageWaitingTime;
            res.queueLength          = kpi.queueLength;
            res.reviewerUtilization  = kpi.reviewerUtilization;

            % Fallback: log the completed count from logsout when the To
            % Workspace variable is unavailable (older / re-instrumented model).
            if isnan(res.completedPatients) ...
                    && isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
                found = false;
                for ei = 1:numel(simOut.logsout)
                    el = simOut.logsout.get(ei);
                    if ~isa(el, 'Simulink.SimulationData.Signal')
                        continue;
                    end
                    if strcmp(el.Name, 'completedPatients')
                        res.completedPatients = last_sample(el);
                        found = true;
                        break;
                    end
                end
                if ~found
                    for ei = 1:numel(simOut.logsout)
                        el = simOut.logsout.get(ei);
                        if isa(el, 'Simulink.SimulationData.Signal')
                            res.completedPatients = last_sample(el);
                            break;
                        end
                    end
                end
            end

            % Compute MEASURED throughput and annual capacity
            % Throughput is only reported for a full simulated workday: a
            % partial window (e.g. the 1h smoke) is NOT extrapolated to a
            % day, which would fabricate a rate the model never produced.
            if ~isnan(res.completedPatients) && p.workHoursPerDay > 0
                if abs(p.simTimeMin - p.workHoursPerDay * 60) < 1e-9
                    res.measurementWindow = 'FULL_WORKDAY';
                    res.throughput = res.completedPatients;   % patients/workday
                    res.annualCapacity = res.throughput * 365;
                else
                    res.measurementWindow = 'PARTIAL_WINDOW';
                    res.throughput = NaN;
                    res.annualCapacity = NaN;
                end
            end

            % Analytical KPI estimates from model parameters (context/labels)
            aStats = compute_analytical_stats(p);
            res.meanWaitingTime     = aStats.meanWaitingTime;
            res.maxWaitingTime      = aStats.maxWaitingTime;
            res.acqUtilization      = aStats.acqUtilization;
            res.aiUtilization       = aStats.aiUtilization;
            res.revUtilization      = aStats.revUtilization;
            res.networkUtilization  = aStats.netUtilization;

            % Identify bottleneck from analytical utilization (ANALYTICAL)
            res.bottleneck = identify_bottleneck(res, p);

            res.executionStatus = 'SUCCESS';
        else
            res.executionStatus = 'FAILED';
            res.bottleneck = 'Unknown';
        end
    catch ME
        res.executionStatus = 'FAILED';
        res.bottleneck = 'Error';
        log_msg('error', sprintf('Simulation failure for scenario "%s": %s', sc, ME.message));
        fail('SimulationFailed', 'Simulation run failed for scenario "%s": %s', sc, ME.message);
    end
end

% -------------------------------------------------------------------------
% Pending scenario helper (non-fabricated results)
% -------------------------------------------------------------------------
function res = pending_scenario(p, sc)
    res = init_result_struct(sc, p);
    res.executionStatus = 'PENDING';
    res.bottleneck      = 'PENDING';
end

% -------------------------------------------------------------------------
% Signal extraction helper
% -------------------------------------------------------------------------
function v = last_sample(el)
%LAST_SAMPLE  Last logged sample of a Simulink signal, NaN when none logged.
%   Empty logging (e.g. no entity ever reached the completed sink) is a
%   legitimate measured '0 completed', surfaced as NaN so the MEASURED
%   throughput logic below treats it as "no throughput measured".
    v = NaN;
    td = el.Values.Data;
    if ~isempty(td)
        v = td(end);
    end
end

% -------------------------------------------------------------------------
% Analytical stats from model parameters (M/M/1 approximations)
% -------------------------------------------------------------------------
function stats = compute_analytical_stats(p)
%COMPUTE_ANALYTICAL_STATS  Estimate utilization and queue stats from params.
%
%   Provides honest analytical estimates based on the same parameters
%   used by the Simulink model. NOT from SimEvents post-sim block stats.
%   Based on M/M/1 queueing theory approximations.

    arrivalRate = 1 / (p.meanArrivalTimeMin * 60);  % patients/sec

    % Service times (seconds)
    acqSvcTime = p.acquisitionTimeMin * 60 / (1 - p.recaptureRate);
    txSvcTime  = p.transmissionDelayS + (p.imageSizeMB * 8 / p.bandwidthMbps);
    aiSvcTime  = p.aiProcessTimeMin * 60;
    revSvcTime = p.reviewTimeMin * 60;

    % Effective arrival rates per stage
    acqArrivalRate = arrivalRate;
    netArrivalRate = arrivalRate * (1 - p.recaptureRate);
    aiArrivalRate  = netArrivalRate;
    revArrivalRate = aiArrivalRate * p.referralRate;

    % Server utilizations (rho = lambda * S)
    stats.acqUtilization = min(acqArrivalRate * acqSvcTime, 1.0);
    stats.netUtilization = min(netArrivalRate * txSvcTime, 1.0);
    stats.aiUtilization  = min(aiArrivalRate * aiSvcTime, 1.0);
    stats.revUtilization = min(revArrivalRate * revSvcTime / p.numReviewers, 1.0);

    % Queue estimates (M/M/1: Lq = rho^2/(1-rho), Wq = rho*S/(1-rho))
    rhoAcq = stats.acqUtilization;
    if rhoAcq < 1
        stats.queueLength = rhoAcq^2 / (1 - rhoAcq);
        stats.meanWaitingTime = rhoAcq * acqSvcTime / (1 - rhoAcq);
    else
        stats.queueLength = NaN;
        stats.meanWaitingTime = NaN;
    end
    stats.maxWaitingTime = stats.meanWaitingTime * 3;  % rough upper bound
end

% -------------------------------------------------------------------------
% Bottleneck identification (from analytical utilizations)
% -------------------------------------------------------------------------
function bn = identify_bottleneck(res, p)
%IDENTIFY_BOTTLENECK  Determine which resource is the current bottleneck.
%
%   Returns the name of the resource with the highest utilization.
%   Based on analytical estimates, not direct SimEvents measurement.

    utils = [res.acqUtilization, res.networkUtilization, ...
             res.aiUtilization, res.revUtilization];
    names = {'Acquisition', 'Network/Transmission', 'AI Processing', ...
             'Ophthalmologist Review'};

    if all(isnan(utils))
        bn = 'Unknown (stats unavailable)';
        return;
    end

    [~, idx] = max(utils);
    bn = names{idx};
end

% -------------------------------------------------------------------------
% Environment checking helper
% -------------------------------------------------------------------------
function env = check_environment()
    env = struct();
    env.hasSimulink  = false;
    env.hasSimEvents = false;
    env.hasModel     = false;
    env.modelPath    = '';
    env.isExecutable = false;
    env.statusReason = '';

    try
        env.hasSimulink = ~isempty(which('sim')) && license('test', 'Simulink');
    catch
        env.hasSimulink = false;
    end

    try
        env.hasSimEvents = license('test', 'SimEvents');
    catch
        env.hasSimEvents = false;
    end

    simDir = fileparts(mfilename('fullpath'));
    candidate = fullfile(simDir, 'DRTelemedicine.slx');
    if exist(candidate, 'file') == 2
        env.hasModel = true;
        env.modelPath = candidate;
    elseif exist('DRTelemedicine', 'file') == 4
        env.hasModel = true;
        env.modelPath = which('DRTelemedicine');
    end

    reasons = {};
    if ~env.hasSimulink
        reasons{end+1} = 'Simulink unavailable/unlicensed';
    end
    if ~env.hasSimEvents
        reasons{end+1} = 'SimEvents unavailable/unlicensed';
    end
    if ~env.hasModel
        reasons{end+1} = 'DRTelemedicine.slx missing';
    end

    if isempty(reasons)
        env.isExecutable = true;
        env.statusReason = 'Ready';
    else
        env.isExecutable = false;
        env.statusReason = strjoin(reasons, '; ');
    end
end

% -------------------------------------------------------------------------
% Data structure helpers
% -------------------------------------------------------------------------
function r = init_result_struct(sc, p)
    r = empty_result_struct();
    r.scenario            = sc;
    r.bandwidthMbps       = p.bandwidthMbps;
    r.numReviewers        = p.numReviewers;
    r.patientsPerDay      = p.patientsPerDay;
    r.simTimeHours        = p.simTimeMin / 60;
    if abs(p.simTimeMin - p.workHoursPerDay * 60) < 1e-9
        r.measurementWindow = 'FULL_WORKDAY';
    else
        r.measurementWindow = 'PARTIAL_WINDOW';
    end
end

function r = empty_result_struct()
    r = struct( ...
        'scenario',            '', ...
        'bandwidthMbps',       NaN, ...
        'numReviewers',        NaN, ...
        'patientsPerDay',      NaN, ...
        'simTimeHours',        NaN, ...
        'measurementWindow',   '', ...
        'throughput',          NaN, ...
        'completedPatients',   NaN, ...
        'averageWaitingTime',  NaN, ...
        'meanWaitingTime',     NaN, ...
        'maxWaitingTime',      NaN, ...
        'queueLength',         NaN, ...
        'acqUtilization',      NaN, ...
        'aiUtilization',       NaN, ...
        'revUtilization',      NaN, ...
        'reviewerUtilization', NaN, ...
        'networkUtilization',  NaN, ...
        'bottleneck',          '', ...
        'annualCapacity',      NaN, ...
        'executionStatus',     '');
end

% -------------------------------------------------------------------------
% Display comparison table
% -------------------------------------------------------------------------
function print_results_table(results)
    fprintf('\n%s\n', repmat('=', 1, 110));
    fprintf('  RetinaSense Telemedicine District Simulation Results\n');
    fprintf('  Throughput = MEASURED from SimEvents | Util/Bottleneck = ANALYTICAL\n');
    fprintf('%s\n', repmat('=', 1, 110));
    fprintf('%-18s | %-6s | %-5s | %-8s | %-10s | %-10s | %-8s | %-8s | %-8s | %-10s\n', ...
        'Scenario', 'BW(Mb)', 'Revs', 'Pts/Day', 'Throughput', 'Ann.Cap', ...
        'Acq%', 'AI%', 'Rev%', 'Bottleneck');
    fprintf('%s\n', repmat('-', 1, 110));
    for i = 1:numel(results)
        r = results(i);
        if isnan(r.throughput)
            tpStr = 'N/A';
            acStr = 'N/A';
        else
            tpStr = sprintf('%.1f/day', r.throughput);
            acStr = sprintf('%.0f/yr', r.annualCapacity);
        end
        if isnan(r.acqUtilization)
            aqStr = 'N/A';
        else
            aqStr = sprintf('%.0f%%', r.acqUtilization * 100);
        end
        if isnan(r.aiUtilization)
            aiStr = 'N/A';
        else
            aiStr = sprintf('%.0f%%', r.aiUtilization * 100);
        end
        if isnan(r.revUtilization)
            rvStr = 'N/A';
        else
            rvStr = sprintf('%.0f%%', r.revUtilization * 100);
        end
        fprintf('%-18s | %6.1f | %5d | %8d | %-10s | %-10s | %-8s | %-8s | %-8s | %-10s\n', ...
            r.scenario, r.bandwidthMbps, r.numReviewers, r.patientsPerDay, ...
            tpStr, acStr, aqStr, aiStr, rvStr, r.bottleneck);
    end
    fprintf('%s\n\n', repmat('=', 1, 110));
end

% -------------------------------------------------------------------------
% Detailed KPI report per scenario
% -------------------------------------------------------------------------
function print_kpi_report(results)
%PRINT_KPI_REPORT  Display detailed KPI statistics for each scenario.
%   Clearly labels which values are MEASURED vs ANALYTICAL.

    fprintf('\n%s\n', repmat('=', 1, 80));
    fprintf('  DETAILED KPI STATISTICS PER SCENARIO\n');
    fprintf('%s\n', repmat('=', 1, 80));

    for i = 1:numel(results)
        r = results(i);
        fprintf('\n--- Scenario: %s ---\n', r.scenario);
        fprintf('  Execution:          %s\n', r.executionStatus);
        fprintf('  Patients/day (cfg): %d\n', r.patientsPerDay);
        fprintf('  Bandwidth:          %.1f Mbps\n', r.bandwidthMbps);
        fprintf('  Reviewers:          %d\n', r.numReviewers);

        if strcmp(r.executionStatus, 'SUCCESS')
            fprintf('  --- MEASURED (from simulation) ---\n');
            fprintf('  Completed patients: %d (in %g-hour simulation window, %s)\n', ...
                r.completedPatients, r.simTimeHours, r.measurementWindow);
            if ~isnan(r.throughput)
                fprintf('  Throughput:         %.1f patients/workday (MEASURED)\n', r.throughput);
                fprintf('  Annual capacity:    %.0f patients/year (workday x 365)\n', r.annualCapacity);
            else
                fprintf('  Throughput:         not reported (partial window; no daily extrapolation)\n');
            end
            fprintf('  Avg wait (Acq queue): %.1f sec (MEASURED)\n', r.averageWaitingTime);
            fprintf('  Avg queue length:     %.2f entities (MEASURED)\n', r.queueLength);
            fprintf('  Reviewer util:        %.1f%% (MEASURED)\n', r.reviewerUtilization * 100);
            fprintf('  --- ANALYTICAL (M/M/1 estimates from params) ---\n');
            fprintf('  Mean waiting time:  %.1f sec\n', r.meanWaitingTime);
            fprintf('  Max waiting time:   %.1f sec (est.)\n', r.maxWaitingTime);
            fprintf('  Acquisition util:   %.1f%%\n', r.acqUtilization * 100);
            fprintf('  Network util:       %.1f%%\n', r.networkUtilization * 100);
            fprintf('  AI Processing util: %.1f%%\n', r.aiUtilization * 100);
            fprintf('  Review util:        %.1f%%\n', r.revUtilization * 100);
            fprintf('  Bottleneck:         %s\n', r.bottleneck);
        else
            fprintf('  Status: %s (KPIs not available)\n', r.executionStatus);
        end
    end
    fprintf('\n%s\n\n', repmat('=', 1, 80));
end

% -------------------------------------------------------------------------
% JSON persistence (real simulation results, never fabricated)
% -------------------------------------------------------------------------
function outPath = persist_results_json(results)
%PERSIST_RESULTS_JSON  Write measured + analytical scenario results to JSON.
%
%   Writes simulink/output/district_capacity_results_<timestamp>.json so the
%   actual simulation outputs survive the session. Every numeric field in the
%   file is either:
%     MEASURED   - directly from a SimEvents simulation run
%     ANALYTICAL - M/M/1 estimate computed from scenario_params
%   fields that do not apply are null. NaN/Inf are never encoded as JSON
%   numbers.

    simDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(simDir, 'output');
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    ts = datestr(now, 'yyyymmdd_HHMMSS');
    outPath = fullfile(outDir, sprintf('district_capacity_results_%s.json', ts));

    payload = struct();
    payload.generatedAt      = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    payload.matlabVersion    = version();
    payload.simulinkVersion  = safe_ver('simulink');
    payload.simEventsVersion = safe_ver('simevents');
    payload.modelFile        = 'DRTelemedicine.slx';
    payload.dataSourcePolicy = [ ...
        'MEASURED: completedPatients from the SimEvents completed sink; ' ...
        'throughput/annualCapacity only for a FULL_WORKDAY window; ' ...
        'averageWaitingTime/queueLength/reviewerUtilization read directly from ' ...
        'real SimEvents block statistics (Acquisition Queue AverageWait/' ...
        'AverageQueueLength, Review Server Utilization) enabled POST-BUILD as ' ...
        'passive listeners; one dedicated To Workspace per signal. ' ...
        'ANALYTICAL: meanWaitingTime/maxWaitingTime/utilizations/ ' ...
        'bottleneck are M/M/1 estimates from scenario_params. ' ...
        'No value is extrapolated from a partial simulation window.']; %#ok<NBRAK>
    payload.results = sanitize_json(results);

    json = jsonencode(payload, 'PrettyPrint', true);
    fid = fopen(outPath, 'w');
    if fid < 0
        fail('WriteFailed', 'Could not open %s for writing.', outPath);
    end
    fwrite(fid, json, 'char');
    fclose(fid);

    fprintf('\nPersisted results to %s\n', outPath);
end

function v = safe_ver(name)
    % SimEvents' toolbox name changed to 'slde'; 'ver('simevents')' is
    % deprecated and warns. Try non-deprecated names first.
    candidates = {name};
    if strcmp(name, 'simevents')
        candidates = {'slde', 'simevents'};
    end
    v = '';
    for i = 1:numel(candidates)
        try
            vv = ver(candidates{i});
            if ~isempty(vv)
                v = sprintf('%s (%s)', vv(1).Version, strtrim(vv(1).Release));
                return;
            end
        catch
            % try next candidate
        end
    end
end

function s = sanitize_json(x)
%SANITIZE_JSON  Convert NaN/Inf anywhere in x to [] so jsonencode succeeds.
%   Struct ARRAYS become cell arrays (JSON arrays of objects) to keep the
%   element grouping unambiguous for jsonencode.
    if isstruct(x)
        if numel(x) > 1
            s = cell(1, numel(x));
            for i = 1:numel(x)
                s{i} = sanitize_json(x(i));
            end
        else
            s = struct();
            for f = fieldnames(x).'
                s.(f{1}) = sanitize_json(x.(f{1}));
            end
        end
    elseif iscell(x)
        s = cell(size(x));
        for i = 1:numel(x)
            s{i} = sanitize_json(x{i});
        end
    elseif isnumeric(x)
        s = x;
        bad = isnan(x) | isinf(x);
        if any(bad(:))
            s(bad) = [];
        end
    else
        s = x;
    end
end

% -------------------------------------------------------------------------
% Logging and error handling
% -------------------------------------------------------------------------
function log_msg(level, msg)
    if exist('logMessage', 'file') == 2
        logMessage(level, 'run_simulink_scenarios', msg);
    else
        fprintf('[%s] [run_simulink_scenarios] %s\n', upper(level), msg);
    end
end

function fail(code, msg, varargin)
    if exist('raiseError', 'file') == 2
        raiseError('run_simulink_scenarios', code, msg, varargin{:});
    else
        id = sprintf('RetinaSense:run_simulink_scenarios:%s', code);
        error(id, msg, varargin{:});
    end
end
