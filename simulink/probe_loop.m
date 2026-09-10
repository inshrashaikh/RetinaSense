function probe_loop()
%PROBE_LOOP  Deterministic-arrival trace of the recapture loop.
%
%   sc_pl2 : G(const) -> Acq -> Dec -> Gate -> T1        (no loop)
%   sc_lp2 : G(const) -> Merge -> Acq -> Dec -> Gate
%            Gate.out1 -> T1 (forward/completed)
%            Gate.out2 -> Replicator -> { Merge.in2, T2 (recapture count) }
%   Constant arrivals (Period 90 s, service 180 s) make counts exact.

    fprintf('=== DETERMINISTIC LOOP TRACE ===\n');
    load_system('sldelib');

    build_pl2('sc_pl2');
    build_lp2('sc_lp2');

    for mm = {'sc_pl2', 'sc_lp2'}
        mdl = mm{1};
        fprintf('\n--- %s ---\n', upper(mdl));
        for recap = [0.0 0.1 0.5 0.9]
            params = struct('meanArrivalTimeMin', 1.5, 'acquisitionTimeMin', 3.0, ...
                            'recaptureRate', recap, 'simTimeMin', 60);
            assignin('base', 'params', params);
            fprintf('  recaptureRate=%.1f: ', recap);
            try
                set_param(mdl, 'StopTime', 'params.simTimeMin * 60');
                set_param(mdl, 'SimulationCommand', 'update');
                so = sim(mdl);
                vals = struct();
                for j = 1:numel(so.logsout)
                    el = so.logsout.get(j);
                    bp = el.BlockPath.getBlock(1);
                    nm = bp(regexp(bp, '[^/]+$'):end);
                    vals.(nm) = el.Values.Data(end);
                end
                nms = fieldnames(vals);
                for k = 1:numel(nms)
                    fprintf('%s=%g ', nms{k}, vals.(nms{k}));
                end
                fprintf('\n');
            catch ME
                fprintf('FAIL: %s\n', ME.message);
            end
        end
    end
end

function prep(mdl)
    set_param(mdl, 'StopTime', 'params.simTimeMin * 60', ...
        'SolverType', 'Variable-step', 'Solver', 'VariableStepDiscrete', ...
        'SignalLogging', 'on');
end

function build_pl2(mdl)
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    prep(mdl);
    add_block('sldelib/Entity Generator', [mdl '/G']);
    add_block('sldelib/Entity Server',    [mdl '/Acq']);
    add_block('sldelib/Entity Server',    [mdl '/Dec']);
    add_block('sldelib/Entity Output Switch', [mdl '/Gate']);
    add_block('sldelib/Entity Terminator',[mdl '/T1']);
    set_param([mdl '/G'], 'TimeSource', 'Dialog', 'Period', '90', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([mdl '/Acq'], 'Capacity', '1', 'ServiceTimeValue', 'params.acquisitionTimeMin*60');
    set_param([mdl '/Dec'], 'Capacity', '1', 'ServiceTimeValue', '0', ...
        'EntryAction', 'entity.route = 1 + double(rand() < params.recaptureRate);');
    set_param([mdl '/Gate'], 'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    add_line(mdl, 'G/1', 'Acq/1', 'autorouting', 'on');
    add_line(mdl, 'Acq/1', 'Dec/1', 'autorouting', 'on');
    add_line(mdl, 'Dec/1', 'Gate/1', 'autorouting', 'on');
    add_line(mdl, 'Gate/1', 'T1/1', 'autorouting', 'on');
    add_sink(mdl, 'T1');
    save_system(mdl);
end

function build_lp2(mdl)
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    prep(mdl);
    add_block('sldelib/Entity Generator', [mdl '/G']);
    add_block('sldelib/Entity Input Switch', [mdl '/Merge']);
    add_block('sldelib/Entity Server',    [mdl '/Acq']);
    add_block('sldelib/Entity Server',    [mdl '/Dec']);
    add_block('sldelib/Entity Output Switch', [mdl '/Gate']);
    add_block('sldelib/Entity Terminator',[mdl '/T1']);
    add_block('sldelib/Entity Terminator',[mdl '/T2']);
    add_block('sldelib/Entity Replicator',[mdl '/Rep']);
    set_param([mdl '/G'], 'TimeSource', 'Dialog', 'Period', '90', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([mdl '/Merge'], 'ActivePortSelection', 'All', ...
        'SwitchingCriterion', 'Round robin', 'Seed', '0');
    set_param([mdl '/Acq'], 'Capacity', '1', 'ServiceTimeValue', 'params.acquisitionTimeMin*60');
    set_param([mdl '/Dec'], 'Capacity', '1', 'ServiceTimeValue', '0', ...
        'EntryAction', 'entity.route = 1 + double(rand() < params.recaptureRate);');
    set_param([mdl '/Gate'], 'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    add_line(mdl, 'G/1', 'Merge/1', 'autorouting', 'on');
    add_line(mdl, 'Merge/1', 'Acq/1', 'autorouting', 'on');
    add_line(mdl, 'Acq/1', 'Dec/1', 'autorouting', 'on');
    add_line(mdl, 'Dec/1', 'Gate/1', 'autorouting', 'on');
    add_line(mdl, 'Gate/1', 'T1/1', 'autorouting', 'on');
    add_line(mdl, 'Gate/2', 'Rep/1', 'autorouting', 'on');
    add_line(mdl, 'Rep/1', 'Merge/2', 'autorouting', 'on');
    add_line(mdl, 'Rep/2', 'T2/1', 'autorouting', 'on');
    add_sink(mdl, 'T1');
    add_sink(mdl, 'T2');
    save_system(mdl);
end

function add_sink(mdl, name)
    p = [mdl '/' name];
    set_param(p, 'NumberEntitiesArrived', 'on');
    st = [mdl '/ST_' name];
    add_block('built-in/Terminator', st, 'Position', [120 40 140 60]);
    add_line(mdl, [name '/1'], ['ST_' name '/1'], 'autorouting', 'on');
    set_param(get_param(p, 'PortHandles').Outport(1), 'DataLogging', 'on');
end