function probe_merge()
%PROBE_MERGE  Isolate why the Completed Merge reports mismatched structures.

    fprintf('=== MERGE STRUCTURE PROBE ===\n');
    load_system('sldelib');

    % Test A: single generator -> Output Switch ('From attribute') -> both
    % outputs into one Entity Input Switch -> Terminator
    m1 = 'sc_merge_a';
    if bdIsLoaded(m1)
        close_system(m1, 0);
    end
    new_system(m1);
    load_system(m1);
    set_param(m1, 'StopTime', '600');
    add_block('sldelib/Entity Generator',    [m1 '/G']);
    add_block('sldelib/Entity Server',       [m1 '/Decider']);
    add_block('sldelib/Entity Output Switch',[m1 '/Sw']);
    add_block('sldelib/Entity Input Switch', [m1 '/M']);
    add_block('sldelib/Entity Terminator',   [m1 '/T']);
    set_param([m1 '/G'], ...
        'TimeSource', 'Dialog', 'Period', '20', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([m1 '/Decider'], ...
        'ServiceTimeValue', '0', ...
        'EntryAction', 'entity.route = 1 + double(rand() < 0.1);');
    set_param([m1 '/Sw'], ...
        'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    add_line(m1, 'G/1', 'Decider/1', 'autorouting', 'on');
    add_line(m1, 'Decider/1', 'Sw/1', 'autorouting', 'on');
    add_line(m1, 'Sw/1', 'M/1', 'autorouting', 'on');
    add_line(m1, 'Sw/2', 'M/2', 'autorouting', 'on');
    add_line(m1, 'M/1', 'T/1', 'autorouting', 'on');
    rel = compile_check(m1, 'Test A: From-attribute switch outputs into merge');

    % Test B: default criterion switch outputs into merge
    m2 = 'sc_merge_b';
    if bdIsLoaded(m2)
        close_system(m2, 0);
    end
    new_system(m2);
    load_system(m2);
    set_param(m2, 'StopTime', '600');
    add_block('sldelib/Entity Generator',    [m2 '/G']);
    add_block('sldelib/Entity Output Switch',[m2 '/Sw']);
    add_block('sldelib/Entity Input Switch', [m2 '/M']);
    add_block('sldelib/Entity Terminator',   [m2 '/T']);
    set_param([m2 '/G'], ...
        'TimeSource', 'Dialog', 'Period', '20', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    add_line(m2, 'G/1', 'Sw/1', 'autorouting', 'on');
    add_line(m2, 'Sw/1', 'M/1', 'autorouting', 'on');
    add_line(m2, 'Sw/2', 'M/2', 'autorouting', 'on');
    add_line(m2, 'M/1', 'T/1', 'autorouting', 'on');
    rel = compile_check(m2, 'Test B: default-criterion switch outputs into merge');

    % Test C: generator -> merge.in1, generator -> server -> merge.in2
    m3 = 'sc_merge_c';
    if bdIsLoaded(m3)
        close_system(m3, 0);
    end
    new_system(m3);
    load_system(m3);
    set_param(m3, 'StopTime', '600');
    add_block('sldelib/Entity Generator',    [m3 '/G1']);
    add_block('sldelib/Entity Generator',    [m3 '/G2']);
    add_block('sldelib/Entity Input Switch', [m3 '/M']);
    add_block('sldelib/Entity Terminator',   [m3 '/T']);
    set_param([m3 '/G1'], ...
        'TimeSource', 'Dialog', 'Period', '20', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([m3 '/G2'], ...
        'TimeSource', 'Dialog', 'Period', '20', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    add_line(m3, 'G1/1', 'M/1', 'autorouting', 'on');
    add_line(m3, 'G2/1', 'M/2', 'autorouting', 'on');
    add_line(m3, 'M/1', 'T/1', 'autorouting', 'on');
    rel = compile_check(m3, 'Test C: two independent generators into merge');
end

function rel = compile_check(mdl, label)
    rel = 'OK';
    fprintf('\n%s\n', label);
    try
        set_param(mdl, 'SimulationCommand', 'update');
        fprintf('  COMPILE OK\n');
    catch ME
        rel = 'FAIL';
        fprintf('  COMPILE FAIL: %s\n', ME.message);
    end
    try
        close_system(mdl, 0);
        delete([tempdir mdl '.slx']);
    catch
    end
end