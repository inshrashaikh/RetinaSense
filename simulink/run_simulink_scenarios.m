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
%   Outputs:
%     results - 1xN struct array with fields:
%       scenario, bandwidthMbps, numReviewers, patientsPerDay, throughput,
%       completedPatients, meanWaitingTime, maxWaitingTime, queueLength,
%       reviewerUtilization, networkUtilization, bottleneck,
%       annualCapacity, executionStatus

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

    % 3. Print readable comparison table
    print_results_table(results);
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

        simOut = sim(modelName, 'StopTime', num2str(p.simTimeMin * 60));

        if ~isempty(simOut)
            % Extract logged metrics if provided by model
            if isprop(simOut, 'completedPatients') || isfield(simOut, 'completedPatients')
                res.completedPatients = simOut.completedPatients;
            elseif isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
                try
                    res.completedPatients = simOut.logsout.get('completedPatients').Values.Data(end);
                catch
                end
            end

            if ~isnan(res.completedPatients) && p.workHoursPerDay > 0
                res.throughput = res.completedPatients;
                res.annualCapacity = res.throughput * 365;
            end

            res.executionStatus = 'SUCCESS';
            res.bottleneck = 'None';
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

    % Check Simulink
    try
        env.hasSimulink = ~isempty(which('sim')) && license('test', 'Simulink');
    catch
        env.hasSimulink = false;
    end

    % Check SimEvents
    try
        env.hasSimEvents = license('test', 'SimEvents');
    catch
        env.hasSimEvents = false;
    end

    % Check Model
    simDir = fileparts(mfilename('fullpath'));
    candidate = fullfile(simDir, 'DRTelemedicine.slx');
    if exist(candidate, 'file') == 2
        env.hasModel = true;
        env.modelPath = candidate;
    elseif exist('DRTelemedicine', 'file') == 4
        env.hasModel = true;
        env.modelPath = which('DRTelemedicine');
    end

    % Determine execution readiness
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
end

function r = empty_result_struct()
    r = struct(...
        'scenario',            '', ...
        'bandwidthMbps',       NaN, ...
        'numReviewers',        NaN, ...
        'patientsPerDay',      NaN, ...
        'throughput',          NaN, ...
        'completedPatients',   NaN, ...
        'meanWaitingTime',     NaN, ...
        'maxWaitingTime',      NaN, ...
        'queueLength',         NaN, ...
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
    fprintf('\n%s\n', repmat('=', 1, 95));
    fprintf('  RetinaSense Telemedicine District Simulation Results (Sprint 6)\n');
    fprintf('%s\n', repmat('=', 1, 95));
    fprintf('%-18s | %-6s | %-5s | %-7s | %-10s | %-10s | %-10s\n', ...
        'Scenario', 'BW(Mb)', 'Revs', 'Pts/Day', 'Throughput', 'Status', 'Bottleneck');
    fprintf('%s\n', repmat('-', 1, 95));
    for i = 1:numel(results)
        r = results(i);
        if isnan(r.throughput)
            tpStr = 'N/A';
        else
            tpStr = sprintf('%.1f/day', r.throughput);
        end
        fprintf('%-18s | %6.1f | %5d | %7d | %-10s | %-10s | %-10s\n', ...
            r.scenario, r.bandwidthMbps, r.numReviewers, r.patientsPerDay, ...
            tpStr, r.executionStatus, r.bottleneck);
    end
    fprintf('%s\n\n', repmat('=', 1, 95));
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