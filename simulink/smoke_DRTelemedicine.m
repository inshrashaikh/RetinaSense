function status = smoke_DRTelemedicine()
%SMOKE_DRTELEMEDICINE  Load, compile and smoke-run the SimEvents model.
%
%   status = smoke_DRTelemedicine()
%
%   Verifies, against simulink/DRTelemedicine.slx:
%     - the model loads with no unresolved library blocks
%     - it compiles (SimulationCommand 'update')
%     - a short smoke simulation actually runs
%     - entities flow: completedPatients > 0 at the end
%
%   The last check is a HARD FAILURE: completedPatients <= 0 (or NaN, when no
%   'completedPatients' log exists) makes the smoke throw, so a zero-entity
%   model is caught instead of reported as a passing smoke.
%
%   KPI data source: completedPatients, averageWaitingTime, queueLength and
%   reviewerUtilization are all MEASURED from the simulation (SimEvents block
%   Statistics). A missing/invalid real KPI is a HARD FAILURE, so the model
%   cannot pass a smoke without its real KPI instrumentation.
%
%   Outputs: status struct with booleans loads/compiles/simRuns/entitiesFlow,
%   plus completedPatients, averageWaitingTime, queueLength,
%   reviewerUtilization, unresolvedBlocks and ok. Throws
%   RetinaSense:smoke_DRTelemedicine:* on any failure (nonzero exit for CI).

    mdl = 'DRTelemedicine';
    simDir = fileparts(mfilename('fullpath'));
    slx = fullfile(simDir, [mdl '.slx']);

    status = struct( ...
        'loads', false, 'compiles', false, 'simRuns', false, ...
        'entitiesFlow', false, 'ok', false, ...
        'completedPatients', NaN, 'unresolvedBlocks', 0, ...
        'averageWaitingTime', NaN, 'queueLength', NaN, ...
        'reviewerUtilization', NaN, ...
        'message', '');

    fprintf('=== SMOKE: %s ===\n', mdl);

    % -- parameterize (baseline, full workday so every measured observable
    %    is genuinely exercised - the review-server Utilization statistic
    %    stays NaN until a referral actually departs, which rarely happens
    %    inside a 1-hour window) --
    params = scenario_params('baseline');
    params.simTimeMin = params.workHoursPerDay * 60;   % 8h work window
    assignin('base', 'params', params);
    rng(params.seed);

    % -- 1. load --
    try
        if bdIsLoaded(mdl)
            close_system(mdl, 0);
        end
        load_system(slx);
        status.loads = true;
        fprintf('LOAD: OK\n');
    catch ME
        status.message = sprintf('load failed: %s', ME.message);
        fprintf('%s\n', status.message);
        fail('LoadFailed', status.message);
    end

    % -- unresolved blocks check --
    nUn = 0;
    blks = find_system(mdl, 'SearchDepth', 1, 'Type', 'block');
    for b = blks'
        if strcmp(b{1}, mdl)
            continue;
        end
        st = get_param(b{1}, 'LinkStatus');
        if strcmp(st, 'unresolved')
            fprintf('  UNRESOLVED LINK: %s\n', b{1});
            nUn = nUn + 1;
        end
    end
    status.unresolvedBlocks = nUn;
    if nUn > 0
        status.message = sprintf('%d unresolved library block(s)', nUn);
        fprintf('%s\n', status.message);
        fail('UnresolvedLinks', status.message);
    end
    fprintf('UNRESOLVED: none (%d blocks loaded)\n', numel(blks) - 1);

    % -- instrument: runtime KPI observables must be present before compile --
    instrument_for_kpis(mdl);

    % -- 2. compile / update --
    try
        set_param(mdl, 'SimulationCommand', 'update');
        status.compiles = true;
        fprintf('COMPILE: OK\n');
    catch ME
        status.message = sprintf('compile failed: %s', ME.message);
        fprintf('%s\n', status.message);
        fail('CompileFailed', status.message);
    end

    % -- 3. smoke simulation --
    try
        simOut = sim(mdl);
        status.simRuns = true;
        fprintf('SIM: OK\n');

        % Real KPIs (MEASURED: post-build SimEvents block statistics -> To Workspace)
        kpi = measured_kpis(simOut, params);
        status.completedPatients   = kpi.completed;
        status.averageWaitingTime  = kpi.averageWaitingTime;
        status.queueLength         = kpi.queueLength;
        status.reviewerUtilization = kpi.reviewerUtilization;

        % completedPatients must come from the completed sink count.
        n = status.completedPatients;
        fprintf('completedPatients (8h smoke) = %g\n', n);

        if isnan(n) || n <= 0
            status.message = sprintf('completedPatients = %g (must be > 0)', n);
            fprintf('SMOKE FAIL: %s\n', status.message);
            fail('NoEntitiesFlow', status.message);
        end
        status.entitiesFlow = true;
        fprintf('SMOKE CHECK entities-flow: OK (completedPatients > 0)\n');

        fprintf('REAL KPIs (8h smoke):\n');
        fprintf('  averageWaitingTime = %g s  queueLength = %g  reviewerUtilization = %.1f%%\n', ...
            status.averageWaitingTime, status.queueLength, ...
            status.reviewerUtilization * 100);
        if isnan(status.averageWaitingTime) || isnan(status.queueLength) ...
                || isnan(status.reviewerUtilization)
            status.message = 'missing real KPI stat (wait/queue length/utilization)';
            fprintf('SMOKE FAIL: %s\n', status.message);
            fail('KpiMissing', status.message);
        end
        if status.averageWaitingTime < 0 || status.queueLength < 0 ...
                || status.reviewerUtilization < 0 || status.reviewerUtilization > 1
            status.message = 'invalid real KPI value (negative or out-of-range)';
            fprintf('SMOKE FAIL: %s\n', status.message);
            fail('KpiInvalid', status.message);
        end

        % Analytical estimates (upper-bound sanity context only, not the KPI)
        aStats = compute_analytical_stats(params);
        fprintf('Analytical estimates (context only):\n');
        fprintf('  Acq util: %.1f%%  Net util: %.1f%%  AI util: %.1f%%  Rev util: %.1f%%\n', ...
            aStats.acqUtilization * 100, aStats.netUtilization * 100, ...
            aStats.aiUtilization * 100, aStats.revUtilization * 100);
    catch ME
        if strncmp(ME.identifier, 'RetinaSense:smoke_DRTelemedicine:', 32)
            rethrow(ME);
        end
        status.message = sprintf('sim failed: %s', ME.message);
        fprintf('SIM: FAIL - %s\n', ME.message);
        fail('SimulationFailed', status.message);
    end

    status.ok = status.loads && status.compiles && status.simRuns && ...
        status.entitiesFlow && status.unresolvedBlocks == 0;
    fprintf('--- SMOKE RESULT ---\n');
    fprintf(['  loads=%d compiles=%d simRuns=%d entitiesFlow=%d completed=%g ', ...
        'wait=%g qlen=%g revUtil=%.1f%% unresolved=%d\n'], ...
        status.loads, status.compiles, status.simRuns, status.entitiesFlow, ...
        status.completedPatients, status.averageWaitingTime, ...
        status.queueLength, status.reviewerUtilization * 100, status.unresolvedBlocks);
    fprintf('  RESULT: %s\n', ternary(status.ok, 'PASS', 'FAIL'));
end

function stats = compute_analytical_stats(p)
    arrivalRate = 1 / (p.meanArrivalTimeMin * 60);
    acqSvcTime = p.acquisitionTimeMin * 60 / (1 - p.recaptureRate);
    txSvcTime  = p.transmissionDelayS + (p.imageSizeMB * 8 / p.bandwidthMbps);
    aiSvcTime  = p.aiProcessTimeMin * 60;
    revSvcTime = p.reviewTimeMin * 60;

    stats.acqUtilization = min(arrivalRate * acqSvcTime, 1.0);
    stats.netUtilization = min(arrivalRate * (1 - p.recaptureRate) * txSvcTime, 1.0);
    stats.aiUtilization  = min(arrivalRate * (1 - p.recaptureRate) * aiSvcTime, 1.0);
    stats.revUtilization = min(arrivalRate * (1 - p.recaptureRate) * p.referralRate * revSvcTime / p.numReviewers, 1.0);
end

function s = ternary(cond, a, b)
    if cond
        s = a;
    else
        s = b;
    end
end

function fail(code, msg)
    id = sprintf('RetinaSense:smoke_DRTelemedicine:%s', code);
    error(id, '%s', msg);
end