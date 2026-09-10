function probe_block_params()
%PROBE_BLOCK_PARAMS  Verify settable dialog parameters and runtime behavior.
%
%   Adds each R2026a SimEvents entity block into a scratch model, dumps its
%   dialog parameters and description, then configures and RUNS a miniature
%   version of the RetinaSense flow to verify:
%     - base-workspace 'params' is visible in dialog expressions
%     - 'params' / rand() are visible in runtime actions (inter-generation
%       time, server entry actions)
%     - the recapture feedback loop through an Entity Input Switch compiles
%       and runs.

    fprintf('=== CONFIG PROBE (R2026a SimEvents) ===\n');
    load_system('sldelib');

    mdl = 'sc_config_probe';
    if bdIsLoaded(mdl)
        close_system(mdl, 0);
    end
    new_system(mdl);
    load_system(mdl);
    set_param(mdl, 'StopTime', '360');

    params = struct( ...
        'meanArrivalTimeMin', 1.75, ...
        'acquisitionTimeMin', 3.0, ...
        'transmissionDelayS', 15, ...
        'imageSizeMB', 8, ...
        'bandwidthMbps', 2, ...
        'aiProcessTimeMin', 1.5, ...
        'queueCapacity', 200, ...
        'recaptureRate', 0.10, ...
        'referralRate', 0.08, ...
        'reviewTimeMin', 5, ...
        'numReviewers', 2, ...
        'simTimeMin', 480, ...
        'seed', 42);
    assignin('base', 'params', params);
    rng(params.seed);

    B = struct();
    B.gen   = [mdl '/Arrival'];
    B.merge = [mdl '/Merge'];
    B.acq   = [mdl '/Acquisition'];
    B.gate  = [mdl '/QualityGate'];
    B.sink  = [mdl '/Sink'];

    add_block('sldelib/Entity Generator',   B.gen);
    add_block('sldelib/Entity Input Switch', B.merge);
    add_block('sldelib/Entity Server',       B.acq);
    add_block('sldelib/Entity Output Switch',B.gate);
    add_block('sldelib/Entity Terminator',   B.sink);

    fprintf('\n--- DIALOG PARAMETERS ---\n');
    blks = {B.gen, B.merge, B.acq, B.gate, B.sink};
    for i = 1:numel(blks)
        dump_dialog(blks{i});
    end

    fprintf('\n--- CONFIGURE & RUN ---\n');
    try
        % Arrival: exponential inter-generation time referencing 'params'
        set_param(B.gen, ...
            'TimeSource', 'MATLAB action', ...
            'IntergenerationTimeAction', ...
                'dt = -params.meanArrivalTimeMin*60*log(1-rand());', ...
            'EntityType', 'Structured', ...
            'EntityTypeName', 'Entity', ...
            'AttributeName', 'route', ...
            'AttributeInitialValue', '0');

        % Acquisition server: dialog time referencing 'params' (evaluated at
        % update time in base workspace)
        set_param(B.acq, ...
            'Capacity', '1', ...
            'ServiceTimeValue', 'params.acquisitionTimeMin*60');

        % Quality gate: route on attribute 'route', 1 -> forward, 2 -> retake
        set_param(B.gate, 'SwitchAttributeName', 'route');

        % Wire: Arrival -> Merge.in1 ; Merge -> Acq -> Gate.out1 -> Sink ;
        % Gate.out2 -> Merge.in2 (recapture feedback loop)
        add_line(mdl, 'Arrival/1', 'Merge/1', 'autorouting', 'on');
        add_line(mdl, 'Merge/1', 'Acquisition/1', 'autorouting', 'on');
        add_line(mdl, 'Acquisition/1', 'QualityGate/1', 'autorouting', 'on');
        add_line(mdl, 'QualityGate/1', 'Sink/1', 'autorouting', 'on');
        add_line(mdl, 'QualityGate/2', 'Merge/2', 'autorouting', 'on');

        fprintf('Updating/compiling...\n');
        set_param(mdl, 'SimulationCommand', 'update');
        fprintf('COMPILE OK\n');

        fprintf('Running smoke sim (360 s)...\n');
        t0 = tic;
        simOut = sim(mdl);
        fprintf('SIM OK elapsed %.1f s\n', toc(t0));
    catch ME
        fprintf('CONFIG/RUN FAIL: %s\n', ME.message);
        for k = 1:numel(ME.stack)
            fprintf('  at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
        end
    end

    close_system(mdl, 0);
    try
        delete([tempdir mdl '.slx']);
    catch
    end
end

% -------------------------------------------------------------------------
function resolve_block_paths()
end

% -------------------------------------------------------------------------
function dump_dialog(blk)
    fprintf('  [%s]\n', blk);
    try
        dp = get_param(blk, 'DialogParameters');
        fn = fieldnames(dp);
        if isempty(fn)
            fprintf('    (no dialog parameters)\n');
        end
        for i = 1:numel(fn)
            nm = fn{i};
            assignable = '';
            try
                if isfield(dp.(nm), 'Assignable')
                    assignable = sprintf(' assignable=%d', dp.(nm).Assignable);
                end
            catch
            end
            val = '';
            try
                val = get_param(blk, nm);
                if ischar(val)
                    val = strtrim(val);
                    if numel(val) > 80
                        val = [val(1:80) '...'];
                    end
                end
            catch
                val = '';
            end
            fprintf('    %-32s = %s%s\n', nm, num2str(val), assignable);
        end
    catch ME
        fprintf('    dialog error: %s\n', ME.message);
    end
end