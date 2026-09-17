function instrument_for_kpis(mdlName)
%INSTRUMENT_FOR_KPIS  Post-build runtime KPI observables on DRTelemedicine.
%
%   instrument_for_kpis(mdlName)
%
%   R2026a constraint discovered (probe_kpi15/probe_portmap): enabling a
%   SimEvents block statistic DURING build changes the entity structure that
%   flows through queue/server blocks and breaks every Entity Input Switch
%   merge ("All input ports of block ... must have the same entity
%   structure"). Enabling the SAME statistics AFTER the model is built (via
%   set_param) does NOT touch entity structure, and the statistics are pure
%   passive listeners - throughput is unchanged (143/day baseline verified).
%
%   When statistics are enabled post-build, SimEvents PREPENDS the stat
%   signal output ports and pushes the block's entity output port to the LAST
%   position (existing entity lines re-map automatically, verified by
%   probe_portmap). Stat output order follows the dialog field order. For
%   this model (verified numerically on zero-perturbation runs + Little's
%   law): the AverageWait signal is out1 and the AverageQueueLength signal is
%   out2; the entity stream is out3.
%       Acquisition Queue (AverageWait + AverageQueueLength) ->
%           out1 = AverageWait, out2 = AverageQueueLength, out3 = entity
%       Ophthalmologist Review Server (Utilization) ->
%           out1 = Utilization, out2 = entity
%       Completed Screening Sink (NumberEntitiesArrived, already on) ->
%           out1 = cumulative completed count
%
%   Each observable is streamed by ONE dedicated 'To Workspace' block
%   (R2026a forbids Muxing SimEvents stat ports - "use one observation block
%   per signal"): kpiQWait, kpiQLen, kpiRevUtil, kpiCompleted.
%
%   Idempotent: if the instrument blocks already exist, does nothing.
    if nargin < 1 || isempty(mdlName)
        mdlName = 'DRTelemedicine';
    end
    mdl = mdlName;
    if ~bdIsLoaded(mdl)
        load_system(mdl);
    end

    % ---- Idempotency: skip if already instrumented ----
    wsNames = {'kpiQWait', 'kpiQLen', 'kpiRevUtil', 'kpiCompleted'};
    if getSimulinkBlockHandle([mdl '/WS_kpiQWait']) > 0
        fprintf('KPIs instrumented already (%s); skipping.\n', mdl);
        return;
    end

    % ---- Enable statistics post-build (passive listeners) ----
    set_param([mdl '/Acquisition Queue'], ...
        'AverageWait', 'on', ...
        'AverageQueueLength', 'on');
    set_param([mdl '/Ophthalmologist Review Server'], ...
        'Utilization', 'on');
    fprintf('Enabled queue (AverageWait, AverageQueueLength) and review (Utilization) stats.\n');

    % ---- Verify port layout assumptions (fail loudly if they shift) ----
    qph = get_param([mdl '/Acquisition Queue'], 'PortHandles');
    sph = get_param([mdl '/Ophthalmologist Review Server'], 'PortHandles');
    snk = get_param([mdl '/Completed Screening Sink'], 'PortHandles');
    if numel(qph.Outport) < 3
        error('RetinaSense:instrument_for_kpis:UnexpectedQueuePorts', ...
            'Acquisition Queue has %d outports (expected >= 3 with w+l stats).', ...
            numel(qph.Outport));
    end
    if numel(sph.Outport) < 2
        error('RetinaSense:instrument_for_kpis:UnexpectedServerPorts', ...
            'Review Server has %d outports (expected >= 2 with Utilization).', ...
            numel(sph.Outport));
    end
    if numel(snk.Outport) < 1
        error('RetinaSense:instrument_for_kpis:SinkNoStat', ...
            'Completed Sink has no stat output port.');
    end

    % ---- Per-signal To Workspace observers ----
    % Queue: out1 = AverageWait, out2 = AverageQueueLength (entity = out3).
    % Review: out1 = Utilization (entity = out2).
    % Sink:   out1 = NumberEntitiesArrived (cumulative completed count).
    wsSpecs = { ...
        'Acquisition Queue/1',            'kpiQWait'; ...
        'Acquisition Queue/2',            'kpiQLen'; ...
        'Ophthalmologist Review Server/1', 'kpiRevUtil'; ...
        'Completed Screening Sink/1',     'kpiCompleted'};
    for w = 1:size(wsSpecs, 1)
        srcPort = wsSpecs{w, 1};
        wsBlkName = ['WS_' wsSpecs{w, 2}];
        add_block('simulink/Sinks/To Workspace', [mdl '/' wsBlkName], ...
            'VariableName', wsSpecs{w, 2}, 'SaveFormat', 'Timeseries', ...
            'Position', [1500 320 1570 350]);
        add_line(mdl, srcPort, [wsBlkName '/1'], 'autorouting', 'on');
    end
    fprintf('KPIs instrumented: kpiQWait, kpiQLen, kpiRevUtil, kpiCompleted.\n');
end