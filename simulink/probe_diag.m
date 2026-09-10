function probe_diag()
%PROBE_DIAG  Stage-by-stage throughput decomposition of the rebuilt model.
%
%   Builds DRTelemedicine_diag (per-stage NumberEntitiesDeparted counters),
%   then runs a set of flow configurations and reports the counter at each
%   stage to locate where entities are aggregated / stalled.

    fprintf('=== DIAGNOSTIC STAGE-COUNTER PROBE ===\n');
    build_DRTelemedicine('DRTelemedicine_diag', true);

    mdl = 'DRTelemedicine_diag';
    load_system(fullfile(pwd, [mdl '.slx']));

    % Find the added stat ports (outport 2 = NumberEntitiesDeparted)
    statBlocks = { ...
        'Acquisition Server', 'Recapture Decider', 'Transmission Server', ...
        'AI FIFO Queue', 'AI Processing Server', 'Referral Decider', ...
        'Ophthalmologist Review Server'};
    for i = 1:numel(statBlocks)
        ph = get_param([mdl '/' statBlocks{i}], 'PortHandles');
        for j = 1:numel(ph.Outport)
            try
                set_param(ph.Outport(j), 'DataLogging', 'on');
            catch
            end
        end
    end

    cfgs = {
      'A baseline           (arr=105s, recap=.1, ref=.3)', ...
        struct('meanArrivalTimeMin', 1.75, 'recaptureRate', 0.1, 'referralRate', 0.3);
      'B low-load, no gates  (arr=5min, gates=0)', ...
        struct('meanArrivalTimeMin', 5,   'recaptureRate', 0.0, 'referralRate', 0.0);
      'C heavy, recapture only (arr=105s, recap=.9, ref=0)', ...
        struct('meanArrivalTimeMin', 1.75,'recaptureRate', 0.9, 'referralRate', 0.0);
      'D heavy, referrals only (arr=105s, recap=0, ref=0.9)', ...
        struct('meanArrivalTimeMin', 1.75,'recaptureRate', 0.0, 'referralRate', 0.9);
    };

    for i = 1:size(cfgs, 1)
        p = cfgs{i,2};
        params = scenario_params('baseline');
        params.meanArrivalTimeMin = p.meanArrivalTimeMin;
        params.recaptureRate = p.recaptureRate;
        params.referralRate = p.referralRate;
        params.simTimeMin = 60;
        assignin('base', 'params', params);
        rng(42);
        fprintf('\n--- %s ---\n', cfgs{i,1});
        try
            set_param(mdl, 'SimulationCommand', 'update');
            so = sim(mdl);
            dump_all(so);
        catch ME
            fprintf('  FAIL: %s\n', ME.message);
            for k = 1:numel(ME.stack)
                fprintf('    at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
            end
        end
    end
    close_system(mdl, 0);
end

function dump_all(so)
    fprintf('  logsout elements: %d\n', numel(so.logsout));
    for j = 1:numel(so.logsout)
        try
            el = so.logsout.get(j);
            if ~isa(el, 'Simulink.SimulationData.Signal')
                continue;
            end
            bp = el.BlockPath.getBlock(1);
            nm = bp(regexp(bp, '[^/]+$'):end);
            fprintf('    %-40s -> %g\n', nm, el.Values.Data(end));
        catch
            fprintf('    element %d unreadable\n', j);
        end
    end
end