function inspect_simevents_blocks()
%INSPECT_SIMEVENTS_BLOCKS  Diagnostic for the installed R2026a SimEvents library.
%
%   Dumps, for the installed MATLAB/Simulink/SimEvents:
%     1. Environment info (versions, licenses)
%     2. The SimEvents library file path and whether it loads
%     3. Exact library block paths for the blocks RetinaSense needs
%     4. Mask parameter names/defaults for each block
%     5. Port names and compiled port types from a real scratch-model compile
%
%   Nothing is written to disk except a scratch model (removed afterwards).

    ok = start_diag();
    if ~ok
        return;
    end

    lib = resolve_library();
    if isempty(lib)
        fprintf('FATAL: could not load any SimEvents library.\n');
        return;
    end

    % ---- Full flat block list of the library ----
    fprintf('\n=== FULL LIBRARY BLOCK LIST ===\n');
    list_all_blocks(lib);

    % ---- Blocks we need, by partial name match ----
    need = { ...
        'Entity Generator', ...
        'Entity Server', ...
        'Entity Queue', ...
        'Entity Output Switch', ...
        'Entity Input Switch', ...
        'Entity Terminator', ...
        'Entity Gate', ...
        'Entity Replicator', ...
        'Entity Store', ...
        'Entity Transport Delay', ...
        'Multicast Receive Queue'};

    fprintf('\n=== LIBRARY BLOCK RESOLUTION ===\n');
    resolved = struct('name', {}, 'path', {});
    for i = 1:numel(need)
        hits = find_system(lib, 'SearchDepth', 1, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                           'Type', 'block', 'Name', need{i});
        if isempty(hits)
            fprintf('  [NOT FOUND] %s\n', need{i});
        else
            hit = hits{1};
            fprintf('  [FOUND]     %s  ->  %s\n', need{i}, hit);
            resolved(end+1).name = need{i}; %#ok<AGROW>
            resolved(end).path  = hit;      %#ok<AGROW>
        end
    end

    % ---- Ports/external interfaces of resolved library blocks ----
    fprintf('\n=== LIBRARY BLOCK PORT INTERFACES ===\n');
    for i = 1:numel(resolved)
        dump_ports(resolved(i).path);
    end

    % ---- Mask parameters for resolved library blocks ----
    fprintf('\n=== MASK PARAMETERS (library blocks) ===\n');
    for i = 1:numel(resolved)
        dump_mask(resolved(i).path);
    end

    % ---- Compile a scratch chain to get real port types ----
    fprintf('\n=== SCRATCH-MODEL PORT TYPE VERIFICATION ===\n');
    verify_port_types(resolved);
end

% -------------------------------------------------------------------------
function ok = start_diag()
    fprintf('=== ENVIRONMENT ===\n');
    fprintf('MATLAB version    : %s\n', version);
    try
        fprintf('Release           : %s\n', matlabRelease.Release);
    catch
    end
    fprintf('Simulink  license : %d (installed file: %s)\n', ...
        license('test', 'Simulink'), exist(fullfile(matlabroot,'toolbox','simulink'), 'dir'));
    fprintf('SimEvents license : %d\n', license('test', 'SimEvents'));
    try
        v = ver('SimEvents');
        if ~isempty(v)
            fprintf('SimEvents ver     : %s (%s)\n', v.Version, v.Release);
        else
            fprintf('SimEvents ver     : (ver returned empty)\n');
        end
    catch ME
        fprintf('SimEvents ver err : %s\n', ME.message);
    end
    fprintf('matlabroot        : %s\n', matlabroot);
    ok = true;
end

% -------------------------------------------------------------------------
function lib = resolve_library()
    fprintf('\n=== LIBRARY DISCOVERY ===\n');
    lib = '';

    % Resolve the SimEvents library via the SimEvents (slde) install dir
    libFile = '';
    sldeDir = fullfile(matlabroot, 'toolbox', 'slde');
    if exist(sldeDir, 'dir')
        s = dir(fullfile(sldeDir, '**', '*.slx'));
        for f = s'
            if strcmp(f.name, 'sldelib.slx')
                libFile = fullfile(f.folder, f.name);
                fprintf('SimEvents library file : %s\n', libFile);
                break;
            end
        end
    end

    names = {'sldelib', libFile};
    for i = 1:numel(names)
        if isempty(names{i})
            continue;
        end
        try
            load_system(names{i});
            [~, nm] = fileparts(names{i});
            fprintf('load_system(%s) -> OK (library root "%s")\n', names{i}, nm);
            lib = nm;
            return;
        catch ME
            fprintf('load_system(%s) -> FAIL: %s\n', names{i}, ME.message);
        end
    end

    fprintf('No SimEvents library file found.\n');
end

% -------------------------------------------------------------------------
function list_all_blocks(lib)
    names = find_system(lib, 'SearchDepth', 1, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
                        'Type', 'block');
    for i = 1:numel(names)
        if strcmp(names{i}, lib)
            continue;
        end
        fprintf('  %s\n', names{i});
    end
    lookup = dir(fullfile(matlabroot, 'toolbox', 'slde', '**', 'sldelib.slx'));
    if ~isempty(lookup)
        lpath = fullfile(lookup(1).folder, lookup(1).name);
        fprintf('  (library file: %s)\n', lpath);
    end
end

% -------------------------------------------------------------------------
function dump_mask(blk)
    fprintf('  [mask] %s\n', blk);
    try
        m = Simulink.Mask.get(blk);
        if isempty(m)
            fprintf('    (no mask)\n');
            return;
        end
        fprintf('    type: %s  display: %s\n', m.Type, m.Display);
        for i = 1:numel(m.Parameters)
            p = m.Parameters(i);
            fprintf('    par %-28s = "%s"\n', p.Name, p.Value);
        end
    catch ME
        fprintf('    mask error: %s\n', ME.message);
    end
end

% -------------------------------------------------------------------------
function verify_port_types(resolved)
    scratch = 'sc_scratch_simevents';
    if bdIsLoaded(scratch)
        close_system(scratch, 0);
    end
    new_system(scratch);
    load_system(scratch);
    set_param(scratch, 'StopTime', '600');

    gen    = find_block(resolved, 'Entity Generator');
    queue  = find_block(resolved, 'Entity Queue');
    server = find_block(resolved, 'Entity Server');
    inSw   = find_block(resolved, 'Entity Input Switch');
    outSw  = find_block(resolved, 'Entity Output Switch');
    term   = find_block(resolved, 'Entity Terminator');

    added = containers.Map('KeyType', 'char', 'ValueType', 'char');
    if ~isempty(gen)
        bg = [scratch '/Arrival'];
        add_block(gen, bg, 'Position', [20 40 60 80]);
        added('gen') = bg;
        bg2 = [scratch '/Arrival2'];
        add_block(gen, bg2, 'Position', [20 160 60 200]);
        added('gen2') = bg2;
    end
    if ~isempty(inSw)
        bm = [scratch '/Merge'];
        add_block(inSw, bm, 'Position', [100 30 140 90]);
        added('merge') = bm;
    end
    if ~isempty(server)
        bs = [scratch '/Server'];
        add_block(server, bs, 'Position', [180 40 220 90]);
        added('server') = bs;
        bt = [scratch '/Server2'];
        add_block(server, bt, 'Position', [420 160 460 210]);
        added('server2') = bt;
    end
    if ~isempty(outSw)
        bgw = [scratch '/Switch'];
        add_block(outSw, bgw, 'Position', [260 30 310 100]);
        added('switch') = bgw;
    end
    if ~isempty(queue)
        bq = [scratch '/Queue'];
        add_block(queue, bq, 'Position', [500 160 540 210]);
        added('queue') = bq;
    end
    if ~isempty(term)
        bterm = [scratch '/Term'];
        add_block(term, bterm, 'Position', [660 30 700 90]);
        added('term') = bterm;
        bterm2 = [scratch '/Term2'];
        add_block(term, bterm2, 'Position', [660 160 700 220]);
        added('term2') = bterm2;
    end

    % Give the feedback-loop server a nonzero service delay (avoid 0-delay loop)
    if added.isKey('server')
        try
            set_param(added('server'), 'ServiceTimeValue', '30');
        catch
        end
    end

    % Chain A (recapture-loop topology):
    %   Arrival -> Merge.in1 ; Merge.out -> Server -> Switch
    %   Switch.out1 -> Term ; Switch.out2 -> Merge.in2 (feedback loop)
    if added.isKey('gen') && added.isKey('merge')
        add_line(scratch, 'Arrival/1', 'Merge/1', 'autorouting', 'on');
    end
    if added.isKey('merge') && added.isKey('server')
        add_line(scratch, 'Merge/1', 'Server/1', 'autorouting', 'on');
    end
    if added.isKey('server') && added.isKey('switch')
        add_line(scratch, 'Server/1', 'Switch/1', 'autorouting', 'on');
    end
    if added.isKey('switch') && added.isKey('term')
        add_line(scratch, 'Switch/1', 'Term/1', 'autorouting', 'on');
    end
    if added.isKey('switch') && added.isKey('merge')
        add_line(scratch, 'Switch/2', 'Merge/2', 'autorouting', 'on');
    end

    % Chain B (queue + server plumbing):
    %   Arrival2 -> Server2 -> Queue -> Term2
    if added.isKey('gen2') && added.isKey('server2')
        add_line(scratch, 'Arrival2/1', 'Server2/1', 'autorouting', 'on');
    end
    if added.isKey('server2') && added.isKey('queue')
        add_line(scratch, 'Server2/1', 'Queue/1', 'autorouting', 'on');
    end
    if added.isKey('queue') && added.isKey('term2')
        add_line(scratch, 'Queue/1', 'Term2/1', 'autorouting', 'on');
    end

    fprintf('Scratch model blocks:\n');
    blks = find_system(scratch, 'Type', 'block');
    for b = blks'
        fprintf('  %s\n', b{1});
    end

    fprintf('\nPorts (PortHandles) per block:\n');
    for b = blks'
        bn = b{1};
        if strcmp(bn, scratch)
            continue;
        end
        dump_ports(bn);
    end

    % compile the chain
    fprintf('\nUpdating/compiling scratch model...\n');
    try
        set_param(scratch, 'SimulationCommand', 'update');
        fprintf('  COMPILE OK\n');
    catch ME
        fprintf('  COMPILE FAIL: %s\n', ME.message);
    end

    % now dump compiled port types
    fprintf('\nCompiled port types:\n');
    for b = blks'
        bn = b{1};
        if strcmp(bn, scratch)
            continue;
        end
        dump_ports_compiled(bn);
    end

    close_system(scratch, 0);
    try
        delete([tempdir scratch '.slx']);
    catch
    end
end

% -------------------------------------------------------------------------
function p = find_block(resolved, name)
    p = '';
    for i = 1:numel(resolved)
        if strcmp(resolved(i).name, name)
            p = resolved(i).path;
            return;
        end
    end
end

% -------------------------------------------------------------------------
function dump_ports(bn)
    ph = get_param(bn, 'PortHandles');
    fmt = '  %-40s in=';
    fprintf(fmt, bn);
    for i = 1:numel(ph.Inport)
        fprintf('%d(%s) ', i, get_param(ph.Inport(i), 'Name'));
    end
    fprintf(' out=');
    for i = 1:numel(ph.Outport)
        fprintf('%d(%s) ', i, get_param(ph.Outport(i), 'Name'));
    end
    fprintf('\n');
end

% -------------------------------------------------------------------------
function dump_ports_compiled(bn)
    ph = get_param(bn, 'PortHandles');
    fprintf('  compiled %-40s in=', bn);
    for i = 1:numel(ph.Inport)
        try
            t = get_param(ph.Inport(i), 'CompiledPortType');
        catch
            t = 'n/a';
        end
        fprintf('%d[%s] ', i, t);
    end
    fprintf(' out=');
    for i = 1:numel(ph.Outport)
        try
            t = get_param(ph.Outport(i), 'CompiledPortType');
        catch
            t = 'n/a';
        end
        fprintf('%d[%s] ', i, t);
    end
    fprintf('\n');
end