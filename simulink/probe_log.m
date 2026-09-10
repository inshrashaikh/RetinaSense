function probe_log()
%PROBE_LOG  Inspect what signal data a smoke run actually produces.

    fprintf('=== SIGNAL LOGGING PROBE ===\n');
    mdl = 'DRTelemedicine';
    load_system(fullfile(pwd, [mdl '.slx']));

    params = scenario_params('baseline');
    params.simTimeMin = 60;
    assignin('base', 'params', params);
    rng(params.seed);

    % What is on the sink outport and the stat line?
    sink = [mdl '/Completed Screening Sink'];
    ph = get_param(sink, 'PortHandles');
    fprintf('Sink outports: %d\n', numel(ph.Outport));
    for i = 1:numel(ph.Outport)
        try, dl = get_param(ph.Outport(i), 'DataLogging'); catch, dl = '?'; end
        try, n  = get_param(ph.Outport(i), 'DataLoggingName'); catch, n = '?'; end
        fprintf('  out%d DataLogging=%s Name=%s\n', i, dl, n);
    end

    % Line from sink to the stat terminator
    lines = find_system(mdl, 'FindAll', 'on', 'Type', 'line');
    fprintf('Total lines: %d\n', numel(lines));

    simOut = sim(mdl);
    fprintf('\nlogsout element names:\n');
    try
        names = simOut.logsout.getElementNames();
        for i = 1:numel(names)
            fprintf('  [%d] %s\n', i, names{i});
        end
        if isempty(names)
            fprintf('  (empty)\n');
        end
    catch ME
        fprintf('  error: %s\n', ME.message);
    end

    fprintf('\nSimulationOutput fields:\n');
    try
        f = fieldnames(simOut);
        for i = 1:numel(f)
            fprintf('  %s\n', f{i});
        end
    catch ME
        fprintf('  error: %s\n', ME.message);
    end

    fprintf('\nTry extracting from logsout:\n');
    try
        s = simOut.logsout.get(1);
        fprintf('  element1 class=%s\n', class(s));
        try
            fprintf('  element1 name=%s\n', s.Name);
            fprintf('  element1 Values.Data(end)=%g\n', s.Values.Data(end));
        catch ME
            fprintf('  values access failed: %s\n', ME.message);
        end
    catch ME
        fprintf('  get(1) failed: %s\n', ME.message);
    end

    close_system(mdl, 0);
end