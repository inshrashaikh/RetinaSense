function probe_stats()
%PROBE_STATS  Build + run the full RetinaSense flow with R2026a entity blocks.
%
%   Patient Arrival -> Acquisition -> Recapture Gate -> Transmission ->
%   AI Queue -> AI Server -> Referral Router -> Review Queue ->
%   N Reviewers -> Completed Sink. Recapture loops back to Acquisition.
%
%   Verifies compile + smoke run + a nonzero completedPatients signal.

    fprintf('=== FULL-CHAIN PROBE (R2026a SimEvents) ===\n');
    load_system('sldelib');

    mdl = 'sc_full_probe';
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

    B = struct();
    B.arrival    = [mdl '/Patient Arrival'];
    B.mergeIn    = [mdl '/Recapture Merge'];
    B.acq        = [mdl '/Acquisition Server'];
    B.acqDec     = [mdl '/Recapture Decider'];
    B.gate       = [mdl '/Recapture Quality Gate'];
    B.tx         = [mdl '/Transmission Server'];
    B.aiQueue    = [mdl '/AI FIFO Queue'];
    B.ai         = [mdl '/AI Processing Server'];
    B.refDec     = [mdl '/Referral Decider'];
    B.router     = [mdl '/Referral Router'];
    B.revQueue   = [mdl '/Review Queue'];
    B.review     = [mdl '/Ophthalmologist Review Server'];
    B.mergeOut   = [mdl '/Completed Merge'];
    B.sink       = [mdl '/Completed Screening Sink'];

    % ---- Create blocks from the actual sldelib library ----
    add_block('sldelib/Entity Generator',    B.arrival);
    add_block('sldelib/Entity Input Switch', B.mergeIn);
    add_block('sldelib/Entity Server',       B.acq);
    add_block('sldelib/Entity Server',       B.acqDec);
    add_block('sldelib/Entity Output Switch',B.gate);
    add_block('sldelib/Entity Server',       B.tx);
    add_block('sldelib/Entity Queue',        B.aiQueue);
    add_block('sldelib/Entity Server',       B.ai);
    add_block('sldelib/Entity Server',       B.refDec);
    add_block('sldelib/Entity Output Switch',B.router);
    add_block('sldelib/Entity Queue',        B.revQueue);
    add_block('sldelib/Entity Server',       B.review);
    add_block('sldelib/Entity Input Switch', B.mergeOut);
    add_block('sldelib/Entity Terminator',   B.sink);

    % ---- Configure ----
    % Arrival: exponential inter-generation time from 'params'
    set_param(B.arrival, ...
        'TimeSource', 'MATLAB action', ...
        'IntergenerationTimeAction', ...
            'dt = -params.meanArrivalTimeMin*60*log(1-rand());', ...
        'EntityType', 'Structured', ...
        'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', ...
        'AttributeInitialValue', '0');

    % Merges: accept entities on all input ports
    set_param(B.mergeIn,  'ActivePortSelection', 'All');
    set_param(B.mergeOut, 'ActivePortSelection', 'All');

    % Acquisition: dialog service time from params
    set_param(B.acq, 'Capacity', '1', ...
        'ServiceTimeValue', 'params.acquisitionTimeMin*60');

    % Recapture decider: 0-time, re-decides each traversal
    set_param(B.acqDec, ...
        'Capacity', '1', ...
        'ServiceTimeValue', '0', ...
        'EntryAction', ...
            'entity.route = 1 + double(rand() < params.recaptureRate);');

    % Recapture gate: route attribute 1 -> forward (out1), 2 -> retake (out2)
    set_param(B.gate, ...
        'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', ...
        'NumberOutputPorts', '2');

    % Transmission: dialog time from params (bandwidth/image size)
    set_param(B.tx, 'Capacity', '1', ...
        'ServiceTimeValue', ...
            'params.transmissionDelayS + (params.imageSizeMB*8/params.bandwidthMbps)');

    % AI FIFO queue
    set_param(B.aiQueue, 'Capacity', 'params.queueCapacity');

    % AI processing
    set_param(B.ai, 'Capacity', '1', ...
        'ServiceTimeValue', 'params.aiProcessTimeMin*60');

    % Referral decider
    set_param(B.refDec, ...
        'Capacity', '1', ...
        'ServiceTimeValue', '0', ...
        'EntryAction', ...
            'entity.route = 1 + double(rand() < params.referralRate);');

    % Referral router: 1 -> non-referral (out1), 2 -> review (out2)
    set_param(B.router, ...
        'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', ...
        'NumberOutputPorts', '2');

    % Review queue
    set_param(B.revQueue, 'Capacity', 'params.reviewQueueCapacity');

    % N reviewers as a capacity-N server; log utilization + wait stats
    set_param(B.review, ...
        'Capacity', 'params.numReviewers', ...
        'ServiceTimeValue', 'params.reviewTimeMin*60', ...
        'NumberEntitiesDeparted', 'on', ...
        'Utilization', 'on', ...
        'AverageWait', 'on');

    % Sink: count completed patients
    set_param(B.sink, 'NumberEntitiesArrived', 'on');

    % ---- Wire the approved flow ----
    add_line(mdl, 'Patient Arrival/1',      'Recapture Merge/1',   'autorouting', 'on');
    add_line(mdl, 'Recapture Merge/1',      'Acquisition Server/1','autorouting', 'on');
    add_line(mdl, 'Acquisition Server/1',   'Recapture Decider/1', 'autorouting', 'on');
    add_line(mdl, 'Recapture Decider/1',    'Recapture Quality Gate/1', 'autorouting', 'on');
    add_line(mdl, 'Recapture Quality Gate/1','Transmission Server/1','autorouting','on');
    add_line(mdl, 'Recapture Quality Gate/2','Recapture Merge/2',  'autorouting', 'on'); % loop
    add_line(mdl, 'Transmission Server/1',  'AI FIFO Queue/1',     'autorouting', 'on');
    add_line(mdl, 'AI FIFO Queue/1',        'AI Processing Server/1','autorouting','on');
    add_line(mdl, 'AI Processing Server/1', 'Referral Decider/1',  'autorouting', 'on');
    add_line(mdl, 'Referral Decider/1',     'Referral Router/1',   'autorouting', 'on');
    add_line(mdl, 'Referral Router/1',      'Completed Merge/1',   'autorouting', 'on'); % non-referral
    add_line(mdl, 'Referral Router/2',      'Review Queue/1',      'autorouting', 'on'); % referral
    add_line(mdl, 'Review Queue/1',         'Ophthalmologist Review Server/1', 'autorouting', 'on');
    add_line(mdl, 'Ophthalmologist Review Server/1', 'Completed Merge/2', 'autorouting', 'on');
    add_line(mdl, 'Completed Merge/1',      'Completed Screening Sink/1', 'autorouting', 'on');

    fprintf('Blocks created: %d\n', numel(find_system(mdl, 'SearchDepth', 1, 'Type', 'block')));

    % ---- Stats ports ----
    fprintf('\n[Port layout after enabling stats]\n');
    dump_ports(B.review);
    dump_ports(B.sink);

    % Wire the completed-patients statistic to signal logging
    ph = get_param(B.sink, 'PortHandles');
    outPorts = ph.Outport;
    fprintf('Sink has %d output port(s)\n', numel(outPorts));
    if numel(outPorts) >= 2
        % port 1 = entity path (already wired). stat ports follow.
        add_block('built-in/Terminator', [mdl '/CompletedStat'], ...
            'Position', [820 150 850 180]);
        lp = add_line(mdl, 'Completed Screening Sink/2', 'CompletedStat/1', ...
            'autorouting', 'on');
        set_param(lp, 'DataLogging', 'on');
        set_param(lp, 'DataLoggingName', 'completedPatients');
        fprintf('  wired Completed Screening Sink/2 -> logged as completedPatients\n');
    else
        fprintf('Wait: expected a stat output port on the sink.\n');
    end

    fprintf('\nCompiling...\n');
    try
        set_param(mdl, 'SimulationCommand', 'update');
        fprintf('  COMPILE OK\n');
    catch ME
        fprintf('  COMPILE FAIL: %s\n', ME.message);
        for k = 1:numel(ME.stack)
            fprintf('    at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
        end
        close_system(mdl, 0);
        return;
    end

    fprintf('Running smoke sim (1 h)...\n');
    try
        simOut = sim(mdl);
        fprintf('  SIM OK\n');
        try
            cs = simOut.logsout.get('completedPatients');
            fprintf('  completedPatients final = %g\n', cs.Values.Data(end));
        catch ME
            fprintf('  completedPatients extraction failed: %s\n', ME.message);
        end
    catch ME
        fprintf('  SIM FAIL: %s\n', ME.message);
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

% -------------------------------------------------------------------------
function dump_ports(bn)
    ph = get_param(bn, 'PortHandles');
    fprintf('  %-45s in=', bn);
    if isfield(ph, 'Inport')
        for i = 1:numel(ph.Inport)
            fprintf('%d(%s) ', i, get_param(ph.Inport(i), 'Name'));
        end
    end
    fprintf(' out=');
    if isfield(ph, 'Outport')
        for i = 1:numel(ph.Outport)
            fprintf('%d(%s) ', i, get_param(ph.Outport(i), 'Name'));
        end
    end
    fprintf('\n');
end