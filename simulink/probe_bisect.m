function probe_bisect()
%PROBE_BISECT  Stage-by-stage compile of the full RetinaSense chain.

    fprintf('=== CHAIN BISECTION PROBE ===\n');
    load_system('sldelib');

    mdl = 'sc_bisect';
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    set_param(mdl, 'StopTime', '3600');

    params = scenario_params('baseline');
    params.simTimeMin = 60;
    assignin('base', 'params', params);
    rng(params.seed);

    A = mdl;
    % Blocks
    add_block('sldelib/Entity Generator',    [A '/Patient Arrival']);
    add_block('sldelib/Entity Input Switch', [A '/Recapture Merge']);
    add_block('sldelib/Entity Server',       [A '/Acquisition Server']);
    add_block('sldelib/Entity Server',       [A '/Recapture Decider']);
    add_block('sldelib/Entity Output Switch',[A '/Recapture Quality Gate']);
    add_block('sldelib/Entity Server',       [A '/Transmission Server']);
    add_block('sldelib/Entity Queue',        [A '/AI FIFO Queue']);
    add_block('sldelib/Entity Server',       [A '/AI Processing Server']);
    add_block('sldelib/Entity Server',       [A '/Referral Decider']);
    add_block('sldelib/Entity Output Switch',[A '/Referral Router']);
    add_block('sldelib/Entity Queue',        [A '/Review Queue']);
    add_block('sldelib/Entity Server',       [A '/Ophthalmologist Review Server']);
    add_block('sldelib/Entity Input Switch', [A '/Completed Merge']);
    add_block('sldelib/Entity Terminator',   [A '/Completed Screening Sink']);

    % Configure
    set_param([A '/Patient Arrival'], ...
        'TimeSource', 'MATLAB action', ...
        'IntergenerationTimeAction', 'dt = -params.meanArrivalTimeMin*60*log(1-rand());', ...
        'EntityType', 'Structured', 'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', 'AttributeInitialValue', '0');
    set_param([A '/Recapture Merge'],    'ActivePortSelection', 'All');
    set_param([A '/Completed Merge'],    'ActivePortSelection', 'All');
    set_param([A '/Acquisition Server'], 'ServiceTimeValue', 'params.acquisitionTimeMin*60');
    set_param([A '/Recapture Decider'],  'ServiceTimeValue', '0', ...
        'EntryAction', 'entity.route = 1 + double(rand() < params.recaptureRate);');
    set_param([A '/Recapture Quality Gate'], ...
        'SwitchingCriterion', 'From attribute', 'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    set_param([A '/Transmission Server'], 'ServiceTimeValue', ...
        'params.transmissionDelayS + (params.imageSizeMB*8/params.bandwidthMbps)');
    set_param([A '/AI FIFO Queue'], 'Capacity', 'params.queueCapacity');
    set_param([A '/AI Processing Server'], 'ServiceTimeValue', 'params.aiProcessTimeMin*60');
    set_param([A '/Referral Decider'], 'ServiceTimeValue', '0', ...
        'EntryAction', 'entity.route = 1 + double(rand() < params.referralRate);');
    set_param([A '/Referral Router'], ...
        'SwitchingCriterion', 'From attribute', 'SwitchAttributeName', 'route', 'NumberOutputPorts', '2');
    set_param([A '/Review Queue'], 'Capacity', 'params.reviewQueueCapacity');
    set_param([A '/Ophthalmologist Review Server'], ...
        'Capacity', 'params.numReviewers', 'ServiceTimeValue', 'params.reviewTimeMin*60');
    set_param([A '/Completed Screening Sink'], 'NumberEntitiesArrived', 'on');

    % ---- Stage 1: mainline only (no recapture loop, no review branch) ----
    add_line(mdl, 'Patient Arrival/1',    'Recapture Merge/1',       'autorouting', 'on');
    add_line(mdl, 'Recapture Merge/1',    'Acquisition Server/1',    'autorouting', 'on');
    add_line(mdl, 'Acquisition Server/1', 'Recapture Decider/1',     'autorouting', 'on');
    add_line(mdl, 'Recapture Decider/1',  'Recapture Quality Gate/1','autorouting', 'on');
    add_line(mdl, 'Recapture Quality Gate/1', 'Transmission Server/1', 'autorouting', 'on');
    add_line(mdl, 'Transmission Server/1', 'AI FIFO Queue/1',        'autorouting', 'on');
    add_line(mdl, 'AI FIFO Queue/1',      'AI Processing Server/1',  'autorouting', 'on');
    add_line(mdl, 'AI Processing Server/1','Referral Decider/1',     'autorouting', 'on');
    add_line(mdl, 'Referral Decider/1',   'Referral Router/1',       'autorouting', 'on');
    add_line(mdl, 'Referral Router/1',    'Completed Merge/1',       'autorouting', 'on');
    add_line(mdl, 'Completed Merge/1',    'Completed Screening Sink/1', 'autorouting', 'on');
    step(mdl, 'Stage 1: mainline');

    % ---- Stage 2: add recapture feedback loop ----
    add_line(mdl, 'Recapture Quality Gate/2', 'Recapture Merge/2', 'autorouting', 'on');
    step(mdl, 'Stage 2: recapture loop');

    % ---- Stage 3: add review branch through the second merge ----
    add_line(mdl, 'Referral Router/2', 'Review Queue/1', 'autorouting', 'on');
    add_line(mdl, 'Review Queue/1',    'Ophthalmologist Review Server/1', 'autorouting', 'on');
    add_line(mdl, 'Ophthalmologist Review Server/1', 'Completed Merge/2', 'autorouting', 'on');
    step(mdl, 'Stage 3: review branch into Completed Merge');

    close_system(mdl, 0);
    try
        delete([tempdir mdl '.slx']);
    catch
    end
end

function step(mdl, label)
    fprintf('\n%s\n', label);
    try
        set_param(mdl, 'SimulationCommand', 'update');
        fprintf('  COMPILE OK\n');
    catch ME
        fprintf('  COMPILE FAIL: %s\n', ME.message);
    end
end