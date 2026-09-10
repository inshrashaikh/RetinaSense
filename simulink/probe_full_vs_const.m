function probe_full_vs_const()
%PROBE_FULL_VS_CONST  Full model: exponential vs constant arrival pattern.

    fprintf('=== FULL MODEL: EXPONENTIAL vs CONSTANT ARRIVALS ===\n');
    mdl = 'DRTelemedicine';
    load_system(fullfile(pwd, [mdl '.slx']));

    cfgs = {
      'recap=0.1 ref=0.08', struct('recaptureRate', 0.1, 'referralRate', 0.08);
      'recap=0.9 ref=0.00', struct('recaptureRate', 0.9, 'referralRate', 0.00);
    };

    for ci = 1:size(cfgs, 1)
        cfg = cfgs{ci,1};
        fprintf('\n=== %s ===\n', cfg);
        for mode = {'exponential', 'constant'}
            % exponential: leave generator as-is (MATLAB action)
            % constant: switch to Dialog Period=90
            if strcmp(mode{1}, 'constant')
                set_param([mdl '/Patient Arrival Generator'], ...
                    'TimeSource', 'Dialog', 'Period', '90');
            else
                set_param([mdl '/Patient Arrival Generator'], ...
                    'TimeSource', 'MATLAB action', ...
                    'IntergenerationTimeAction', ...
                    'dt = -params.meanArrivalTimeMin*60*log(1-rand());');
            end
            params = scenario_params('baseline');
            params.meanArrivalTimeMin = 1.75;
            params.recaptureRate = cfgs{ci,2}.recaptureRate;
            params.referralRate  = cfgs{ci,2}.referralRate;
            params.simTimeMin = 60;
            assignin('base', 'params', params);
            rng(42);
            fprintf('  %-11s: ', mode{1});
            try
                set_param(mdl, 'SimulationCommand', 'update');
                so = sim(mdl);
                n = count_completed(so);
                fprintf('completed = %g\n', n);
            catch ME
                fprintf('FAIL: %s\n', ME.message);
                for k = 1:numel(ME.stack)
                    fprintf('    at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
                end
            end
        end
    end
    close_system(mdl, 0);
end

function n = count_completed(so)
    n = NaN;
    for j = 1:numel(so.logsout)
        try
            el = so.logsout.get(j);
            if isa(el, 'Simulink.SimulationData.Signal')
                n = el.Values.Data(end);
                return;
            end
        catch
        end
    end
end