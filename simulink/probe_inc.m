function probe_inc()
%PROBE_INC  Incrementally extend the loop model to find the throttling stage.
%
%   inc1: G(const) -> Merge -> Acq -> Dec -> Gate -> T1 | loop
%   inc2: + Tx on the forward branch
%   inc3: + AI Queue + AI Processing on the forward branch
%   inc4: + Referral Decider + Router + Review Queue + Review server +
%         Completed Merge -> sink  (full topology, const arrivals)

    fprintf('=== INCREMENTAL FULL-TOPOLOGY PROBE ===\n');
    load_system('sldelib');

    for inc = 1:4
        mdl = sprintf('sc_inc%d', inc);
        build_inc(mdl, inc);
        fprintf('\n--- %s ---\n', upper(mdl));
        for recap = [0.1 0.9]
            params = struct('meanArrivalTimeMin', 1.5, ...
                'acquisitionTimeMin', 3.0, 'aiProcessTimeMin', 1.5, ...
                'queueCapacity', 200, 'reviewQueueCapacity', 100, ...
                'transmissionDelayS', 15, 'imageSizeMB', 8, 'bandwidthMbps', 2, ...
                'numReviewers', 2, 'reviewTimeMin', 5, ...
                'recaptureRate', recap, 'referralRate', 0.0, 'simTimeMin', 60);
            assignin('base', 'params', params);
            rng(42);
            fprintf('  recap=%.1f: ', recap);
            try
                set_param(mdl, 'StopTime', 'params.simTimeMin * 60');
                set_param(mdl, 'SimulationCommand', 'update');
                so = sim(mdl);
                s = 0;
                for j = 1:numel(so.logsout)
                    try
                        el = so.logsout.get(j);
                        if isa(el, 'Simulink.SimulationData.Signal')
                            s = s + el.Values.Data(end);
                        end
                    catch
                    end
                end
                fprintf('sink total = %g\n', s);
            catch ME
                fprintf('FAIL: %s\n', ME.message);
                for k = 1:numel(ME.stack)
                    fprintf('    at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
                end
            end
        end
    end
end

function build_inc(mdl, inc)
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
    add_line(mdl, 'Gate/2', 'Merge/2', 'autorouting', 'on');

    fwd = 'Gate/1';      % forward path start
    if inc >= 2
        add_block('sldelib/Entity Server', [mdl '/Tx']);
        set_param([mdl '/Tx'], 'Capacity', '1', 'ServiceTimeValue', ...
            'params.transmissionDelayS + (params.imageSizeMB*8/params.bandwidthMbps)');
        add_line(mdl, fwd, 'Tx/1', 'autorouting', 'on');
        fwd = 'Tx/1';
    end
    if inc >= 3
        add_block('sldelib/Entity Queue', [mdl '/AIQ']);
        add_block('sldelib/Entity Server', [mdl '/AI']);
        set_param([mdl '/AIQ'], 'Capacity', 'params.queueCapacity');
        set_param([mdl '/AI'], 'Capacity', '1', 'ServiceTimeValue', 'params.aiProcessTimeMin*60');
        add_line(mdl, fwd, 'AIQ/1', 'autorouting', 'on');
        add_line(mdl, 'AIQ/1', 'AI/1', 'autorouting', 'on');
        fwd = 'AI/1';
    end
    if inc >= 4
        add_block('sldelib/Entity Server', [mdl '/RefDec']);
        add_block('sldelib/Entity Output Switch', [mdl '/Router']);
        add_block('sldelib/Entity Queue', [mdl '/RevQ']);
        add_block('sldelib/Entity Server', [mdl '/Rev']);
        add_block('sldelib/Entity Input Switch', [mdl '/M2']);
        set_param([mdl '/RefDec'], 'Capacity', '1', 'ServiceTimeValue', '0', ...
            'EntryAction', 'entity.route = 1 + double(rand() < params.referralRate);');
        set_param([mdl '/Router'], 'SwitchingCriterion', 'From attribute', ...
            'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
        set_param([mdl '/RevQ'], 'Capacity', 'params.reviewQueueCapacity');
        set_param([mdl '/Rev'], 'Capacity', 'params.numReviewers', ...
            'ServiceTimeValue', 'params.reviewTimeMin*60');
        set_param([mdl '/M2'], 'ActivePortSelection', 'All', ...
            'SwitchingCriterion', 'Round robin', 'Seed', '0');
        add_line(mdl, 'Gate/1', 'RefDec/1', 'autorouting', 'on');
        add_line(mdl, 'RefDec/1', 'Router/1', 'autorouting', 'on');
        add_line(mdl, 'Router/1', 'M2/1', 'autorouting', 'on');
        add_line(mdl, 'Router/2', 'RevQ/1', 'autorouting', 'on');
        add_line(mdl, 'RevQ/1', 'Rev/1', 'autorouting', 'on');
        add_line(mdl, 'Rev/1', 'M2/2', 'autorouting', 'on');
    end

    % sink on the forward tail
    add_block('sldelib/Entity Terminator', [mdl '/Tn']);
    if inc <= 3
        add_line(mdl, fwd, 'Tn/1', 'autorouting', 'on');
    else
        add_line(mdl, 'M2/1', 'Tn/1', 'autorouting', 'on');
    end
    add_sink(mdl, 'Tn');
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