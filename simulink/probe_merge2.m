function probe_merge2()
%PROBE_MERGE2  Entity Input Switch (ActivePortSelection=All) empty-input
%semantics: SKIP-empty vs BLOCK-on-selected-empty.

    fprintf('=== MERGE SEMANTICS PROBE ===\n');
    load_system('sldelib');

    % Common: G1 = 60s -> in1 ; G2 varies -> in2 ; M -> T
    % Test 1: in2 never sends. Skip=>full flow, Block=>zero flow.
    run_case('sc_m1', 'never',    'Test1 in2 empty forever (expect skip: ~51, block: ~0)');
    % Test 2: in2 sends every 500s. 
    run_case('sc_m2', 'occasional','Test2 in2 every 500s');
end

function run_case(mdl, mode, label)
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    set_param(mdl, 'StopTime', '3000');

    add_block('sldelib/Entity Generator', [mdl '/G1']);
    add_block('sldelib/Entity Generator', [mdl '/G2']);
    add_block('sldelib/Entity Input Switch', [mdl '/M']);
    add_block('sldelib/Entity Terminator', [mdl '/T']);

    set_param([mdl '/G1'], 'TimeSource', 'Dialog', 'Period', '60', ...
        'GenerateEntityAtSimulationStart', 'on', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    switch mode
        case 'never'
            set_param([mdl '/G2'], 'TimeSource', 'Dialog', 'Period', '360000', ...
                'GenerateEntityAtSimulationStart', 'off', ...
                'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
                'AttributeName', 'route', 'AttributeInitialValue', '0');
        case 'occasional'
            set_param([mdl '/G2'], 'TimeSource', 'Dialog', 'Period', '500', ...
                'GenerateEntityAtSimulationStart', 'on', ...
                'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
                'AttributeName', 'route', 'AttributeInitialValue', '0');
    end
    set_param([mdl '/M'], 'ActivePortSelection', 'All', ...
        'SwitchingCriterion', 'Round robin', 'Seed', '0');

    add_line(mdl, 'G1/1', 'M/1', 'autorouting', 'on');
    add_line(mdl, 'G2/1', 'M/2', 'autorouting', 'on');
    add_line(mdl, 'M/1', 'T/1', 'autorouting', 'on');
    set_param([mdl '/T'], 'NumberEntitiesArrived', 'on');
    add_block('built-in/Terminator', [mdl '/St'], 'Position', [300 40 320 60]);
    add_line(mdl, 'T/1', 'St/1', 'autorouting', 'on');
    set_param(get_param([mdl '/T'], 'PortHandles').Outport(1), ...
        'DataLogging', 'on', 'DataLoggingName', 'n');

    fprintf('\n%s\n', label);
    try
        set_param(mdl, 'SimulationCommand', 'update');
        so = sim(mdl);
        el = so.logsout.get(1);
        fprintf('  completed(t=3000) = %g\n', el.Values.Data(end));
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