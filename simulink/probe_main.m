function probe_main()
%PROBE_MAIN  Throughput decomposition of the rebuilt model.

    fprintf('=== MAIN MODEL THROUGHPUT DECOMPOSITION ===\n');
    mdl = 'DRTelemedicine';
    load_system(fullfile(pwd, [mdl '.slx']));

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
        fprintf('\n--- %s ---\n', cfgs{i,1});
        p = cfgs{i,2};
        params = scenario_params('baseline');
        params.meanArrivalTimeMin = p.meanArrivalTimeMin;
        params.recaptureRate = p.recaptureRate;
        params.referralRate = p.referralRate;
        params.simTimeMin = 60;
        assignin('base', 'params', params);
        rng(42);
        try
            set_param(mdl, 'SimulationCommand', 'update');
            so = sim(mdl);
            n = count_completed(so);
            fprintf('  completed (1h) = %g\n', n);
        catch ME
            fprintf('  FAIL: %s\n', ME.message);
            for k = 1:numel(ME.stack)
                fprintf('    at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
            end
        end
    end
    close_system(mdl, 0);
end

function n = count_completed(so)
    n = NaN;
    try
        n = so.logsout.get('completedPatients').Values.Data(end);
        return;
    catch
    end
    for j = 1:numel(so.logsout)
        try
            el = so.logsout.get(j);
            if isa(el, 'Simulink.SimulationData.Signal')
                n = el.Values.Data(end);
                fprintf('    (found via logsout element %d)\n', j);
                return;
            end
        catch
        end
    end
end