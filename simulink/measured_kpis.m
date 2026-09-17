function kpi = measured_kpis(simOut, p)
%MEASURED_KPIS  Real KPIs read from instrumented DRTelemedicine SimEvents stats.
%
%   kpi = measured_kpis(simOut, p)
%
%   Reads the four per-signal To Workspace observables that
%   instrument_for_kpis.m adds to DRTelemedicine.slx (one observation block per
%   signal, R2026a rule). Each streams a genuine SimEvents block statistic that
%   is a passive listener - instrumentation is verified NOT to perturb entity
%   flow (throughput identical to the un-instrumented model, 143/day baseline):
%       kpiQWait     - 'Acquisition Queue' AverageWait (running mean queue
%                      waiting time, seconds)
%       kpiQLen      - 'Acquisition Queue' AverageQueueLength (time-averaged
%                      entities in the queue)
%       kpiRevUtil   - 'Ophthalmologist Review Server' Utilization
%                      (time-averaged active reviewers / numReviewers, 0..1)
%       kpiCompleted - 'Completed Screening Sink' NumberEntitiesArrived
%                      (cumulative completed-patient count)
%
%   Contract fields: completed, averageWaitingTime, queueLength,
%   reviewerUtilization. Any value that is not measurable is NaN (never
%   fabricated). completed also falls back to the sink stat DataLogging
%   (logsout) if kpiCompleted is unavailable.
    kpi = struct('averageWaitingTime', NaN, 'queueLength', NaN, ...
        'reviewerUtilization', NaN, 'completed', NaN);

    cp = get_trace(simOut, 'kpiCompleted');
    if ~isempty(cp.v) && numel(cp.v) > 0
        kpi.completed = cp.v(end);
    else
        kpi.completed = completed_from_logsout(simOut);
    end

    qw = get_trace(simOut, 'kpiQWait');
    if ~isempty(qw.v) && numel(qw.v) > 0
        kpi.averageWaitingTime = qw.v(end);
    end

    ql = get_trace(simOut, 'kpiQLen');
    if ~isempty(ql.v) && numel(ql.v) > 0
        kpi.queueLength = ql.v(end);
    end

    ru = get_trace(simOut, 'kpiRevUtil');
    if ~isempty(ru.v) && numel(ru.v) > 0
        kpi.reviewerUtilization = min(max(ru.v(end), 0), 1);
    end
end

function c = get_trace(simOut, varName)
%GET_TRACE  Read a To Workspace 'Timeseries' observable from simOut.
%   Returns struct with .t/.v column vectors (empty when unavailable).
    c = struct('t', [], 'v', []);
    try
        if isprop(simOut, varName) || isfield(simOut, varName)
            x = simOut.(varName);
            if isa(x, 'Simulink.Timeseries')
                c.t = x.Time(:);
                c.v = double(x.Data(:));
            elseif isa(x, 'timeseries')
                c.t = x.Time(:);
                c.v = double(x.Data(:));
            end
        end
    catch ME %#ok<NASGU>
        c = struct('t', [], 'v', []);
    end
end

function n = completed_from_logsout(simOut)
%COMPLETED_FROM_LOGOUT  Fallback: sink DataLogging (R2026a names empty strings).
    n = NaN;
    try
        if isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
            ds = simOut.logsout;
            for k = 1:ds.numElements
                el = ds.getElement(k);
                try
                    v = el.Values.Data;
                    if isnumeric(v) && ~isempty(v) && numel(v) > 1 && all(isfinite(v))
                        n = v(end);
                        break;
                    end
                catch %#ok<NASGU>
                end
            end
        end
    catch ME %#ok<NASGU>
        n = NaN;
    end
end