function probe_stages()
%PROBE_STAGES  Isolate the recapture loop's effect on throughput.
%
%   M_PIPELINE: G -> Acq -> Decider -> Gate -> T1/forward, T2/recapture
%               (no loop; counts where entities go)
%   M_LOOP    : G -> Merge -> Acq -> Decider -> Gate -> T1, T2 -> Merge.in2
%               (single recapture loop)
%   Both run 1h. Compares effective forward completions vs the full model.

    fprintf('=== STAGE/LOOP-ISOLATION PROBE ===\n');
    load_system('sldelib');

    args = { 'sc_pl', 'sc_lp' };
    build_pipeline('sc_pl');
    build_loop('sc_lp');

    for i = 1:2
        mdl = args{i};
        fprintf('\n--- %s ---\n', upper(mdl));
        for recap = [0.1 0.9]
            params = struct('meanArrivalTimeMin', 1.75, 'acquisitionTimeMin', 3.0, ...
                            'recaptureRate', recap, 'simTimeMin', 60);
            assignin('base', 'params', params);
            rng(42);
            fprintf('  recaptureRate=%.1f: ', recap);
            try
                set_param(mdl, 'StopTime', 'params.simTimeMin * 60');
                set_param(mdl, 'SimulationCommand', 'update');
                so = sim(mdl);
                n = numel(so.logsout);
                for j = 1:n
                    el = so.logsout.get(j);
                    bp = el.BlockPath.getBlock(1);
                    nm = bp(regexp(bp, '[^/]+$'):end);
                    fprintf('%s=%g ', nm, el.Values.Data(end));
                end
                fprintf('\n');
            catch ME
                fprintf('FAIL: %s\n', ME.message);
            end
        end
    end
end

function build_pipeline(mdl)
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    set_param(mdl, 'StopTime', 'params.simTimeMin * 60', ...
        'SolverType', 'Variable-step', 'Solver', 'VariableStepDiscrete', ...
        'SignalLogging', 'on');
    add_block('sldelib/Entity Generator', [mdl '/G']);
    add_block('sldelib/Entity Server',    [mdl '/Acq']);
    add_block('sldelib/Entity Server',    [mdl '/Dec']);
    add_block('sldelib/Entity Output Switch', [mdl '/Gate']);
    add_block('sldelib/Entity Terminator',[mdl '/T1']);
    add_block('sldelib/Entity Terminator',[mdl '/T2']);
    set_param([mdl '/G'], 'TimeSource', 'MATLAB action', ...
        'IntergenerationTimeAction', 'dt = -params.meanArrivalTimeMin*60*log(1-rand());', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([mdl '/Acq'], 'Capacity', '1', ...
        'ServiceTimeValue', 'params.acquisitionTimeMin*60');
    set_param([mdl '/Dec'], 'Capacity', '1', 'ServiceTimeValue', '0', ...
        'EntryAction', 'entity.route = 1 + double(rand() < params.recaptureRate);');
    set_param([mdl '/Gate'], 'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    add_line(mdl, 'G/1', 'Acq/1', 'autorouting', 'on');
    add_line(mdl, 'Acq/1', 'Dec/1', 'autorouting', 'on');
    add_line(mdl, 'Dec/1', 'Gate/1', 'autorouting', 'on');
    add_line(mdl, 'Gate/1', 'T1/1', 'autorouting', 'on');
    add_line(mdl, 'Gate/2', 'T2/1', 'autorouting', 'on');
    terms = {'T1', 'T2'};
    for j = 1:2
        set_param([mdl '/' terms{j}], 'NumberEntitiesArrived', 'on');
        add_block('built-in/Terminator', [mdl sprintf('/St%d', j)], ...
            'Position', [300 40+j*40 320 60+j*40]);
        add_line(mdl, [terms{j} '/1'], sprintf('St%d/1', j), 'autorouting', 'on');
        set_param(get_param([mdl '/' terms{j}], 'PortHandles').Outport(1), ...
            'DataLogging', 'on');
    end
    save_system(mdl);
end

function build_loop(mdl)
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    set_param(mdl, 'StopTime', 'params.simTimeMin * 60', ...
        'SolverType', 'Variable-step', 'Solver', 'VariableStepDiscrete', ...
        'SignalLogging', 'on');
    add_block('sldelib/Entity Generator', [mdl '/G']);
    add_block('sldelib/Entity Input Switch', [mdl '/Merge']);
    add_block('sldelib/Entity Server',    [mdl '/Acq']);
    add_block('sldelib/Entity Server',    [mdl '/Dec']);
    add_block('sldelib/Entity Output Switch', [mdl '/Gate']);
    add_block('sldelib/Entity Terminator',[mdl '/T1']);
    set_param([mdl '/G'], 'TimeSource', 'MATLAB action', ...
        'IntergenerationTimeAction', 'dt = -params.meanArrivalTimeMin*60*log(1-rand());', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([mdl '/Merge'], 'ActivePortSelection', 'All', ...
        'SwitchingCriterion', 'Round robin', 'Seed', '0');
    set_param([mdl '/Acq'], 'Capacity', '1', ...
        'ServiceTimeValue', 'params.acquisitionTimeMin*60');
    set_param([mdl '/Dec'], 'Capacity', '1', 'ServiceTimeValue', '0', ...
        'EntryAction', 'entity.route = 1 + double(rand() < params.recaptureRate);');
    set_param([mdl '/Gate'], 'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    add_line(mdl, 'G/1', 'Merge/1', 'autorouting', 'on');
    add_line(mdl, 'Merge/1', 'Acq/1', 'autorouting', 'on');
    add_line(mdl, 'Acq/1', 'Dec/1', 'autorouting', 'on');
    add_line(mdl, 'Dec/1', 'Gate/1', 'autorouting', 'on');
    add_line(mdl, 'Gate/1', 'T1/1', 'autorouting', 'on');
    add_line(mdl, 'Gate/2', 'Merge/2', 'autorouting', 'on');
    set_param([mdl '/T1'], 'NumberEntitiesArrived', 'on');
    add_block('built-in/Terminator', [mdl '/St'], 'Position', [300 40 320 60]);
    add_line(mdl, 'T1/1', 'St/1', 'autorouting', 'on');
    set_param(get_param([mdl '/T1'], 'PortHandles').Outport(1), 'DataLogging', 'on');
    save_system(mdl);
end