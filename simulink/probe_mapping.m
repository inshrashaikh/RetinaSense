function probe_mapping()
%PROBE_MAPPING  Verify Output-Switch 'From attribute' port mapping + flux.

    fprintf('=== ATTRIBUTE ROUTING MAPPING PROBE ===\n');
    load_system('sldelib');

    % Test 1: route=1 must exit via branch 1
    run_route('sc_map_1', '1', 'Test1 route=1');
    % Test 2: route=2 must exit via branch 2
    run_route('sc_map_2', '2', 'Test2 route=2');
    % Test 3: random 50/50 split
    run_route('sc_map_3', '', 'Test3 rand<0.5');
    % Test 4: throughput with acquisition bottleneck (arr 100s, service 180s)
    run_flux('sc_flux', 'Test4 acquisition bottleneck');
end

function run_route(mdl, fixedRoute, label)
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    set_param(mdl, 'StopTime', '3000');
    add_block('sldelib/Entity Generator',    [mdl '/G']);
    add_block('sldelib/Entity Server',       [mdl '/D']);
    add_block('sldelib/Entity Output Switch',[mdl '/Sw']);
    add_block('sldelib/Entity Terminator',   [mdl '/T1']);
    add_block('sldelib/Entity Terminator',   [mdl '/T2']);

    ge = 'entity.route = '; %#ok<NASGU>
    if isempty(fixedRoute)
        entry = 'entity.route = 1 + double(rand() < 0.5);';
    else
        entry = ['entity.route = ' fixedRoute ';'];
    end
    set_param([mdl '/G'], ...
        'TimeSource', 'Dialog', 'Period', '100', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([mdl '/D'], 'ServiceTimeValue', '0', 'EntryAction', entry);
    set_param([mdl '/Sw'], ...
        'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    add_line(mdl, 'G/1', 'D/1', 'autorouting', 'on');
    add_line(mdl, 'D/1', 'Sw/1', 'autorouting', 'on');
    add_line(mdl, 'Sw/1', 'T1/1', 'autorouting', 'on');
    add_line(mdl, 'Sw/2', 'T2/1', 'autorouting', 'on');
    set_param([mdl '/T1'], 'NumberEntitiesArrived', 'on');
    set_param([mdl '/T2'], 'NumberEntitiesArrived', 'on');
    add_block('built-in/Terminator', [mdl '/St1'], 'Position', [400 40 420 60]);
    add_block('built-in/Terminator', [mdl '/St2'], 'Position', [400 90 420 110]);
    add_line(mdl, 'T1/1', 'St1/1', 'autorouting', 'on');
    add_line(mdl, 'T2/1', 'St2/1', 'autorouting', 'on');
    set_param(get_param([mdl '/T1'], 'PortHandles').Outport(1), ...
        'DataLogging', 'on', 'DataLoggingName', 'n1');
    set_param(get_param([mdl '/T2'], 'PortHandles').Outport(1), ...
        'DataLogging', 'on', 'DataLoggingName', 'n2');

    fprintf('\n%s\n', label);
    try
        set_param(mdl, 'SimulationCommand', 'update');
        so = sim(mdl);
        names = so.logsout.getElementNames();
        nEl = numel(so.logsout);
        c1 = get_data(so.logsout, 1);
        c2 = get_data(so.logsout, 2);
        fprintf('  elements=%d names={%s} | e1=%g e2=%g (sum=%g)\n', ...
            nEl, strjoin(names, ','), c1, c2, c1 + c2);
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
        for k = 1:numel(ME.stack)
            fprintf('    at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
        end
    end
    close_system(mdl, 0);
    try
        delete([tempdir mdl '.slx']);
    catch
    end
end

function run_flux(mdl, label)
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    set_param(mdl, 'StopTime', '3000');
    add_block('sldelib/Entity Generator', [mdl '/G']);
    add_block('sldelib/Entity Server',    [mdl '/S']);
    add_block('sldelib/Entity Terminator',[mdl '/T']);
    set_param([mdl '/G'], ...
        'TimeSource', 'Dialog', 'Period', '100', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([mdl '/S'], 'Capacity', '1', 'ServiceTimeValue', '180');
    add_line(mdl, 'G/1', 'S/1', 'autorouting', 'on');
    add_line(mdl, 'S/1', 'T/1', 'autorouting', 'on');
    set_param([mdl '/T'], 'NumberEntitiesArrived', 'on');
    add_block('built-in/Terminator', [mdl '/St'], 'Position', [300 40 320 60]);
    add_line(mdl, 'T/1', 'St/1', 'autorouting', 'on');
    set_param(get_param([mdl '/T'], 'PortHandles').Outport(1), ...
        'DataLogging', 'on', 'DataLoggingName', 'n');

    fprintf('\n%s\n', label);
    try
        set_param(mdl, 'SimulationCommand', 'update');
        so = sim(mdl);
        c = element_end(so, 'n');
        fprintf('  completed(t=3000) = %g (theory ~ %g)\n', c, 3000/180);
    catch ME
        fprintf('  FAIL: %s\n', ME.message);
    end
    close_system(mdl, 0);
    try
        delete([tempdir mdl '.slx']);
    catch
    end
end

function v = get_data(ds, i)
    v = NaN;
    try
        el = ds.get(i);
        v = el.Values.Data(end);
    catch ME
        fprintf('  (element %d read failed: %s)\n', i, ME.message);
    end
end