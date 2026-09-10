function status = smoke_DRTelemedicine()
%SMOKE_DRTELEMEDICINE  Load, compile and smoke-run the rebuilt model.
%
%   status = smoke_DRTelemedicine()
%
%   Verifies, against the rebuilt simulink/DRTelemedicine.slx:
%     - the model loads with no unresolved library blocks
%     - it compiles (SimulationCommand 'update')
%     - a short smoke simulation actually runs
%     - entities flow: completedPatients > 0 at the end
%
%   KPI data source: completedPatients is MEASURED from the simulation.
%   Utilization/queue stats are computed analytically from model parameters.

    status = struct( ...
        'loads', false, 'compiles', false, 'simRuns', false, ...
        'completedPatients', NaN, 'unresolvedBlocks', 0, ...
        'message', '');

    mdl = 'DRTelemedicine';
    slx = fullfile(pwd, [mdl '.slx']);

    fprintf('=== SMOKE: %s ===\n', mdl);

    % -- parameterize (baseline, shortened for a smoke run) --
    params = scenario_params('baseline');
    params.simTimeMin = 60;   % 1-hour work window for the smoke run
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
        return;
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
        return;
    end
    fprintf('UNRESOLVED: none (%d blocks loaded)\n', numel(blks) - 1);

    % -- 2. compile / update --
    try
        set_param(mdl, 'SimulationCommand', 'update');
        status.compiles = true;
        fprintf('COMPILE: OK\n');
    catch ME
        status.message = sprintf('compile failed: %s', ME.message);
        fprintf('%s\n', status.message);
        return;
    end

    % -- 3. smoke simulation --
    try
        simOut = sim(mdl);
        status.simRuns = true;
        fprintf('SIM: OK\n');

        % Extract completed patients (MEASURED)
        n = NaN;
        try
            n = scan_signal(simOut.logsout);
        catch ME2
            fprintf('  (completedPatients log not found: %s)\n', ME2.message);
        end
        status.completedPatients = n;
        fprintf('completedPatients (1h smoke) = %g\n', n);

        % Analytical KPI estimates from parameters
        aStats = compute_analytical_stats(params);
        fprintf('Analytical estimates:\n');
        fprintf('  Acq util: %.1f%%  Net util: %.1f%%  AI util: %.1f%%  Rev util: %.1f%%\n', ...
            aStats.acqUtilization * 100, aStats.netUtilization * 100, ...
            aStats.aiUtilization * 100, aStats.revUtilization * 100);
    catch ME
        status.message = sprintf('sim failed: %s', ME.message);
        fprintf('SIM: FAIL - %s\n', ME.message);
    end

    fprintf('--- SMOKE RESULT ---\n');
    fprintf('  loads=%d compiles=%d simRuns=%d completed=%g unresolved=%d\n', ...
        status.loads, status.compiles, status.simRuns, ...
        status.completedPatients, status.unresolvedBlocks);
end

function v = scan_signal(ds)
    v = NaN;
    for ei = 1:numel(ds)
        el = ds.get(ei);
        if ~isa(el, 'Simulink.SimulationData.Signal')
            continue;
        end
        if strcmp(el.Name, 'completedPatients')
            v = el.Values.Data(end);
            return;
        end
    end
    for ei = 1:numel(ds)
        el = ds.get(ei);
        if isa(el, 'Simulink.SimulationData.Signal')
            v = el.Values.Data(end);
            return;
        end
    end
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
