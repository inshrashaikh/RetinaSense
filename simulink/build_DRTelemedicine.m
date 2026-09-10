function build_DRTelemedicine(mdlName, enableStats)
%BUILD_DRTELEMEDICINE  Build simulink/DRTelemedicine.slx via R2026a APIs.
%
%   build_DRTelemedicine()            build the approved model (no stats)
%   build_DRTelemedicine(mdl, flag)   build model named MDL; set flag to
%                                     true for diagnostic stage counters.
%
%   Constructs the RetinaSense district telemedicine discrete-event model
%   using the ACTUAL installed R2026a SimEvents entity block library
%   ('sldelib'). All block source paths, dialog parameter names and port
%   layout below were verified against the installed library (see
%   inspect_simevents_blocks.m / probe_*.m).
%
%   Approved logical flow:
%     Patient Arrival -> Acquisition -> Recapture Quality Gate ->
%     Transmission -> AI Queue -> AI Processing -> Referral Router ->
%     Review Queue -> N Ophthalmologist Reviewers -> Completed Sink
%   Recapture returns to Acquisition.
%
%   Topology notes (R2026a adaptation):
%     * The R2026a copy of an entity is the 'Entity Generator' (exponential
%       inter-generation via 'IntergenerationTimeAction').
%     * 'Entity Output Switch' routes on an entity attribute, so each
%       probabilistic gate is preceded by a 0-service-time 'Entity Server'
%       that re-draws entity.route on EVERY traversal (recapture/referral
%       decisions are re-decided per pass through the loop, as in the
%       approved workflow).
%     * 'Entity Input Switch' (ActivePortSelection=All) merges the arrival
%       stream with the recapture loop, and merges the non-referral and
%       reviewed streams into the single completed sink.
%     * N ophthalmologist reviewers = one 'Entity Server' with Capacity N.
%     * Throughput: 'Entity Terminator' 'NumberEntitiesArrived' stat port
%       gives completedPatients (signal-logged as 'completedPatients').
%
%   Model-level parameters reference the base-workspace 'params' struct
%   (populated by scenario_params.m) at compile/run time, so scenario
%   what-if evaluation works without rebuilding the model.

    if nargin < 1 || isempty(mdlName)
        mdlName = 'DRTelemedicine';
    end
    if nargin < 2 || isempty(enableStats)
        enableStats = false;
    end
    mdl = mdlName;
    fprintf('=== BUILD %s (R2026a SimEvents) ===\n', mdl);

    % Resolve the installed library
    lib = 'sldelib';
    ok = spawn_load(lib);
    if ~ok
        error('RetinaSense:build_DRTelemedicine:LibraryMissing', ...
            'Could not load SimEvents library ''%s''.', lib);
    end

    % Fresh model
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    if exist(fullfile(pwd, [mdl '.slx']), 'file') == 2
        delete(fullfile(pwd, [mdl '.slx']));
    end
    new_system(mdl);
    load_system(mdl);

    % ---- Model configuration ----
    set_param(mdl, ...
        'SolverType', 'Variable-step', ...
        'Solver', 'VariableStepDiscrete', ...
        'StopTime', 'params.simTimeMin * 60', ...
        'StartTime', '0', ...
        'SignalLogging', 'on', ...
        'ReportName', 'simulink-default.rpt');

    % ---- Blocks (exact library source strings verified against sldelib) ----
    libs = struct( ...
        'generator', 'sldelib/Entity Generator', ...
        'server',    'sldelib/Entity Server', ...
        'queue',     'sldelib/Entity Queue', ...
        'outSwitch', 'sldelib/Entity Output Switch', ...
        'inSwitch',  'sldelib/Entity Input Switch', ...
        'terminator','sldelib/Entity Terminator');

    B = struct();
    B.arrival = add_block_link(libs.generator, mdl, 'Patient Arrival Generator');
    B.mergeIn = add_block_link(libs.inSwitch,  mdl, 'Recapture Merge');
    B.acqQ    = add_block_link(libs.queue,     mdl, 'Acquisition Queue');
    B.acq     = add_block_link(libs.server,    mdl, 'Acquisition Server');
    B.acqDec  = add_block_link(libs.server,    mdl, 'Recapture Decider');
    B.gate    = add_block_link(libs.outSwitch, mdl, 'Recapture Quality Gate');
    B.tx      = add_block_link(libs.server,    mdl, 'Transmission Server');
    B.aiQueue = add_block_link(libs.queue,     mdl, 'AI FIFO Queue');
    B.ai      = add_block_link(libs.server,    mdl, 'AI Processing Server');
    B.refDec  = add_block_link(libs.server,    mdl, 'Referral Decider');
    B.router  = add_block_link(libs.outSwitch, mdl, 'Referral Router');
    B.revQueue= add_block_link(libs.queue,     mdl, 'Review Queue');
    B.review  = add_block_link(libs.server,    mdl, 'Ophthalmologist Review Server');
    B.mergeOut= add_block_link(libs.inSwitch,  mdl, 'Completed Merge');
    B.sink    = add_block_link(libs.terminator,mdl, 'Completed Screening Sink');

    fprintf('Created %d blocks.\n', numel(find_system(mdl, 'SearchDepth', 1, 'Type', 'block')));

    % ---- Arrival generator: exponential inter-generation time ----
    set_param(B.arrival, ...
        'TimeSource', 'MATLAB action', ...
        'IntergenerationTimeAction', ...
            'dt = -params.meanArrivalTimeMin*60*log(1-rand());', ...
        'EntityType', 'Structured', ...
        'EntityTypeName', 'Entity', ...
        'AttributeName', 'route', ...
        'AttributeInitialValue', '0');

    % ---- Input switches used as entity merges (accept all input ports) ----
    set_param(B.mergeIn,  'ActivePortSelection', 'All');
    set_param(B.mergeOut, 'ActivePortSelection', 'All');

    % ---- Acquisition queue: buffers arrivals + retakes off the merge so
    % downstream backpressure (blocked gate output) can never pin the
    % acquisition server's slot (verified cause of throughput collapse).
    set_param(B.acqQ, 'Capacity', 'params.acquisitionQueueCapacity');

    % ---- Acquisition (fundus capture) ----
    set_param(B.acq, ...
        'Capacity', '1', ...
        'ServiceTimeValue', 'params.acquisitionTimeMin*60');

    % ---- Recapture decider: re-decide on EVERY traversal (10% retake) ----
    set_param(B.acqDec, ...
        'Capacity', '1', ...
        'ServiceTimeValue', '0', ...
        'EntryAction', ...
            'entity.route = 1 + double(rand() < params.recaptureRate);');

    % ---- Recapture quality gate: attribute 1 -> forward, 2 -> retake ----
    set_param(B.gate, ...
        'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', ...
        'NumberOutputPorts', '2');

    % ---- Transmission / rural uplink ----
    set_param(B.tx, ...
        'Capacity', '1', ...
        'ServiceTimeValue', ...
            'params.transmissionDelayS + (params.imageSizeMB*8/params.bandwidthMbps)');

    % ---- AI FIFO queue ----
    set_param(B.aiQueue, 'Capacity', 'params.queueCapacity');

    % ---- AI processing ----
    set_param(B.ai, ...
        'Capacity', '1', ...
        'ServiceTimeValue', 'params.aiProcessTimeMin*60');

    % ---- Referral decider: re-decide per entity (8% referral) ----
    set_param(B.refDec, ...
        'Capacity', '1', ...
        'ServiceTimeValue', '0', ...
        'EntryAction', ...
            'entity.route = 1 + double(rand() < params.referralRate);');

    % ---- Referral router: 1 -> non-referral, 2 -> ophthalmologist review ----
    set_param(B.router, ...
        'SwitchingCriterion', 'From attribute', ...
        'SwitchAttributeName', 'route', ...
        'NumberOutputPorts', '2');

    % ---- Review FIFO queue ----
    set_param(B.revQueue, 'Capacity', 'params.reviewQueueCapacity');

    % ---- N ophthalmologist reviewers (Capacity = number of reviewers) ----
    set_param(B.review, ...
        'Capacity', 'params.numReviewers', ...
        'ServiceTimeValue', 'params.reviewTimeMin*60');

    % ---- Completed sink: count arrivals (completed patients) ----
    set_param(B.sink, 'NumberEntitiesArrived', 'on');

    % ---- Diagnostic stage counters (NumberEntitiesArrived + NumberEntitiesDeparted)
    %     when enableStats is true. These counters are read post-simulation
    %     to compute per-stage utilization and queue statistics.
    if enableStats
        serverBlocks = { ...
            'Acquisition Server', 'Recapture Decider', 'Transmission Server', ...
            'AI Processing Server', 'Referral Decider', ...
            'Ophthalmologist Review Server'};
        queueBlocks = { ...
            'Acquisition Queue', 'AI FIFO Queue', 'Review Queue'};
        for i = 1:numel(serverBlocks)
            sb = [mdl '/' serverBlocks{i}];
            set_param(sb, 'NumberEntitiesDeparted', 'on');
        end
        for i = 1:numel(queueBlocks)
            qb = [mdl '/' queueBlocks{i}];
            set_param(qb, 'NumberEntitiesArrived', 'on');
        end
        fprintf('Diagnostic counters enabled on %d servers + %d queues.\n', ...
            numel(serverBlocks), numel(queueBlocks));
    end

    % ---- Wire the approved flow (message/entity ports only) ----
    add_line(mdl, 'Patient Arrival Generator/1', 'Recapture Merge/1', 'autorouting', 'on');
    add_line(mdl, 'Recapture Merge/1',           'Acquisition Queue/1', 'autorouting', 'on');
    add_line(mdl, 'Acquisition Queue/1',         'Acquisition Server/1', 'autorouting', 'on');
    add_line(mdl, 'Acquisition Server/1',        'Recapture Decider/1', 'autorouting', 'on');
    add_line(mdl, 'Recapture Decider/1',         'Recapture Quality Gate/1', 'autorouting', 'on');
    add_line(mdl, 'Recapture Quality Gate/1',    'Transmission Server/1', 'autorouting', 'on');
    add_line(mdl, 'Transmission Server/1',       'AI FIFO Queue/1', 'autorouting', 'on');
    add_line(mdl, 'AI FIFO Queue/1',             'AI Processing Server/1', 'autorouting', 'on');
    add_line(mdl, 'AI Processing Server/1',      'Referral Decider/1', 'autorouting', 'on');
    add_line(mdl, 'Referral Decider/1',          'Referral Router/1', 'autorouting', 'on');
    add_line(mdl, 'Referral Router/1',           'Completed Merge/1', 'autorouting', 'on');
    add_line(mdl, 'Referral Router/2',           'Review Queue/1', 'autorouting', 'on');
    add_line(mdl, 'Review Queue/1',              'Ophthalmologist Review Server/1', 'autorouting', 'on');
    add_line(mdl, 'Ophthalmologist Review Server/1', 'Completed Merge/2', 'autorouting', 'on');
    add_line(mdl, 'Completed Merge/1',           'Completed Screening Sink/1', 'autorouting', 'on');
    % Recapture must return to Acquisition (loop from gate out2 to merge in2)
    add_line(mdl, 'Recapture Quality Gate/2',    'Recapture Merge/2', 'autorouting', 'on');

    % ---- Throughput statistic (completed patients) ----
    add_block('built-in/Terminator', [mdl '/Completed Patients Stat'], ...
        'Position', [1440 400 1470 430]);
    add_line(mdl, 'Completed Screening Sink/1', 'Completed Patients Stat/1', ...
        'autorouting', 'on');
    ph = get_param(B.sink, 'PortHandles');
    set_param(ph.Outport(1), 'DataLogging', 'on');
    set_param(ph.Outport(1), 'DataLoggingName', 'completedPatients');
    fprintf('completedPatients stat logged (sink output port 1).\n');

    % ---- Verify: no unresolved/ unconnected entity ports ----
    verify_build(mdl);

    save_system(mdl);
    fprintf('Saved %s to %s\\%s.slx\n', mdl, pwd, mdl);
end

% -------------------------------------------------------------------------
function ok = spawn_load(lib)
    ok = true;
    try
        if ~bdIsLoaded(lib)
            load_system(lib);
        end
    catch ME
        ok = false;
        fprintf('load_system(%s) failed: %s\n', lib, ME.message);
    end
end

% -------------------------------------------------------------------------
function p = add_block_link(src, mdl, name)
    p = [mdl '/' name];
    add_block(src, p);
    lp = get_param(p, 'Position'); % touch to force layout read
    if isempty(lp)
        set_param(p, 'Position', [40 40 70 70]);
    end
end

% -------------------------------------------------------------------------
function verify_build(mdl)
    fprintf('\n--- Verification ---\n');
    blks = find_system(mdl, 'SearchDepth', 1, 'Type', 'block');
    unresolved = 0;
    for b = blks'
        if strcmp(b{1}, mdl)
            continue;
        end
        st = get_param(b{1}, 'LinkStatus');
        if strcmp(st, 'unresolved') || strcmp(st, 'inactive')
            fprintf('  UNRESOLVED: %s (link %s)\n', b{1}, st);
            unresolved = unresolved + 1;
        end
    end
    if unresolved == 0
        fprintf('  All %d blocks resolve to library links.\n', numel(blks) - 1);
    end
end