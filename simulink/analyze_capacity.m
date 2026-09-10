function analysis = analyze_capacity(results)
%ANALYZE_CAPACITY  Bottleneck and district-scale capacity analysis.
%
%   analysis = analyze_capacity()
%   analysis = analyze_capacity(results)
%
%   Analyzes the district-scale screening network across 4 key resources:
%     1. Acquisition (fundus camera service time & recapture loop)
%     2. Network (bandwidth Mbps & image transmission delay)
%     3. AI Processing (inference service time)
%     4. Ophthalmologist Reviewers (specialist review rate & reviewer count)
%
%   Evaluates current capacity against the 100,000 patients/year target
%   (~274 patients/day). Works with simulation outputs from
%   run_simulink_scenarios.m.
%
%   IMPORTANT (AGENTS.md Guardrail):
%     If Simulink execution is PENDING, analytical service bounds are provided
%     as theoretical estimates, but the final capacity conclusion remains
%     PENDING. Simulation results are never fabricated.
%
%   Outputs:
%     analysis - struct with fields:
%       requiredAnnualCapacity, requiredDailyThroughput,
%       executionStatus, targetAchieved, bottleneckResource,
%       currentCapacity, currentCapacityType,
%       resources (acquisition/network/aiProcessing/reviewers),
%       bandwidthImpact, reviewerRequirement, aiImpact,
%       scenarios, scalabilityAnalysis

    targetAnnual = 100000;
    targetDaily  = targetAnnual / 365; % ~273.97 -> 274

    % 1. Retrieve or validate simulation results
    if nargin < 1 || isempty(results)
        try
            results = run_simulink_scenarios();
        catch ME
            fail('ExecutionError', 'Failed to retrieve scenario results: %s', ME.message);
        end
    end

    if ~isstruct(results) || isempty(results)
        fail('InvalidInput', 'results must be a non-empty struct array.');
    end

    % 2. Baseline parameters for baseline analysis
    pBase = scenario_params('baseline');

    % 3. Analyze each individual resource (Analytical bounds)
    resAcq = analyze_acquisition_resource(pBase, targetDaily);
    resNet = analyze_network_resource(pBase, targetDaily);
    resAi  = analyze_ai_resource(pBase, targetDaily);
    resRev = analyze_reviewer_resource(pBase, targetDaily);

    % 4. Resource impact analyses
    bandwidthImpact = evaluate_bandwidth_impact(results, targetDaily);
    reviewerImpact  = evaluate_reviewer_impact(results, targetDaily);
    aiImpact        = evaluate_ai_impact(pBase, targetDaily);

    % 5. Evaluate scenario matrix & execution status
    hasSimSuccess = any(strcmp({results.executionStatus}, 'SUCCESS') & ~isnan([results.throughput]));

    scenarioTable = repmat(empty_scenario_summary(), 1, numel(results));
    for i = 1:numel(results)
        r = results(i);
        scParams = scenario_params(r.scenario);
        scenarioTable(i) = evaluate_scenario_entry(r, scParams, targetDaily);
    end

    % 6. Compile overall analysis structure
    analysis = struct();
    analysis.requiredAnnualCapacity  = targetAnnual;
    analysis.requiredDailyThroughput = targetDaily;

    if hasSimSuccess
        analysis.executionStatus     = 'COMPLETE';
        analysis.targetAchieved      = any([scenarioTable.simulatedCapacity] >= targetAnnual);
        analysis.bottleneckResource  = determine_simulated_bottleneck(results);
        analysis.currentCapacityType = 'SIMULATION_RESULT';
        baseIdx = find(strcmp({results.scenario}, 'baseline'), 1);
        if ~isempty(baseIdx) && ~isnan(results(baseIdx).annualCapacity)
            analysis.currentCapacity = results(baseIdx).annualCapacity;
        else
            analysis.currentCapacity = max([results.annualCapacity]);
        end
    else
        analysis.executionStatus     = 'PENDING';
        analysis.targetAchieved      = 'PENDING (Awaiting Simulink Execution)';
        analysis.bottleneckResource  = sprintf('%s (Analytical Estimate)', resAcq.bottleneckCandidate);
        analysis.currentCapacityType = 'ANALYTICAL_ESTIMATE (SIMULATION_PENDING)';
        analysis.currentCapacity     = NaN;
    end

    analysis.resources = struct(...
        'acquisition', resAcq, ...
        'network',     resNet, ...
        'aiProcessing',resAi, ...
        'reviewers',   resRev);

    analysis.bandwidthImpact     = bandwidthImpact;
    analysis.reviewerRequirement = reviewerImpact;
    analysis.aiImpact            = aiImpact;
    analysis.scenarios           = scenarioTable;

    % 7. Scalability analysis: what is needed for 100,000 patients/year
    analysis.scalabilityAnalysis = compute_scalability_analysis(pBase, targetDaily, targetAnnual, results);

    % 8. Display formatted summary report
    print_capacity_report(analysis);
end

% -------------------------------------------------------------------------
% Resource-specific analytical analyzers
% -------------------------------------------------------------------------
function res = analyze_acquisition_resource(p, targetDaily)
    res = struct();
    % Effective acquisition time accounts for recapture loop
    res.nominalServiceTimeMin = p.acquisitionTimeMin;
    res.recaptureRate         = p.recaptureRate;
    res.effectiveServiceTimeMin = p.acquisitionTimeMin / (1 - p.recaptureRate);
    res.singleStationDailyCapacity = p.simTimeMin / res.effectiveServiceTimeMin;
    res.singleStationAnnualCapacity = res.singleStationDailyCapacity * 365;
    res.utilizationAtTarget = targetDaily / res.singleStationDailyCapacity;
    res.stationsRequiredFor100k = ceil(targetDaily / res.singleStationDailyCapacity);
    if res.utilizationAtTarget > 1.0
        res.bottleneckCandidate = 'Acquisition (Single Camera)';
    else
        res.bottleneckCandidate = 'Acquisition';
    end
end

function res = analyze_network_resource(p, targetDaily)
    res = struct();
    res.imageSizeMB          = p.imageSizeMB;
    res.bandwidthMbps        = p.bandwidthMbps;
    res.transmissionDelayS   = p.transmissionDelayS;
    res.transferTimeS        = (p.imageSizeMB * 8) / p.bandwidthMbps;
    res.totalPerPatientSec   = p.transmissionDelayS + res.transferTimeS;
    res.dailyCapacity        = (p.simTimeMin * 60) / res.totalPerPatientSec;
    res.annualCapacity       = res.dailyCapacity * 365;
    res.utilizationAtTarget  = targetDaily / res.dailyCapacity;
    % Minimum bandwidth required so network utilization < 100%
    availSecPerPatient = (p.simTimeMin * 60) / targetDaily - p.transmissionDelayS;
    if availSecPerPatient > 0
        res.minBandwidthRequiredMbps = (p.imageSizeMB * 8) / availSecPerPatient;
    else
        res.minBandwidthRequiredMbps = Inf;
    end
end

function res = analyze_ai_resource(p, targetDaily)
    res = struct();
    res.aiProcessTimeMin     = p.aiProcessTimeMin;
    res.dailyCapacity        = p.simTimeMin / p.aiProcessTimeMin;
    res.annualCapacity       = res.dailyCapacity * 365;
    res.utilizationAtTarget  = targetDaily / res.dailyCapacity;
    res.maxSustainableDaily  = res.dailyCapacity;
    res.maxAiTimeForTargetMin= p.simTimeMin / targetDaily;
end

function res = analyze_reviewer_resource(p, targetDaily)
    res = struct();
    res.referralRate         = p.referralRate;
    res.reviewTimeMin        = p.reviewTimeMin;
    res.numReviewers         = p.numReviewers;
    res.reviewsPerDayAtTarget= targetDaily * p.referralRate;
    res.reviewsPerReviewerDay= p.simTimeMin / p.reviewTimeMin;
    res.totalReviewCapacityDay = p.numReviewers * res.reviewsPerReviewerDay;
    res.maxScreenedCapacityDay = res.totalReviewCapacityDay / p.referralRate;
    res.annualCapacity       = res.maxScreenedCapacityDay * 365;
    res.utilizationAtTarget  = res.reviewsPerDayAtTarget / res.totalReviewCapacityDay;
    res.minReviewersRequired = ceil(res.reviewsPerDayAtTarget / res.reviewsPerReviewerDay);
end

% -------------------------------------------------------------------------
% Impact evaluators
% -------------------------------------------------------------------------
function bImpact = evaluate_bandwidth_impact(results, targetDaily)
    bws = [1.0, 2.0, 4.0];
    bImpact = struct();
    for i = 1:numel(bws)
        bw = bws(i);
        p = scenario_params('baseline', struct('bandwidthMbps', bw));
        txS = p.transmissionDelayS + (p.imageSizeMB * 8 / bw);
        dailyCap = (p.simTimeMin * 60) / txS;
        fn = sprintf('bw_%dMbps', round(bw));
        bImpact.(fn) = struct(...
            'bandwidthMbps', bw, ...
            'transferTimeS', txS, ...
            'dailyCapacity', dailyCap, ...
            'annualCapacity', dailyCap * 365, ...
            'utilizationAtTarget', targetDaily / dailyCap);
    end
end

function rImpact = evaluate_reviewer_impact(results, targetDaily)
    reviewerCounts = [1, 2, 5];
    rImpact = struct();
    for i = 1:numel(reviewerCounts)
        nRev = reviewerCounts(i);
        p = scenario_params('baseline', struct('numReviewers', nRev));
        revPerDay = targetDaily * p.referralRate;
        revCapacity = nRev * (p.simTimeMin / p.reviewTimeMin);
        fn = sprintf('reviewers_%d', nRev);
        rImpact.(fn) = struct(...
            'numReviewers', nRev, ...
            'reviewCapacityDay', revCapacity, ...
            'screenedCapacityDay', revCapacity / p.referralRate, ...
            'utilizationAtTarget', revPerDay / revCapacity, ...
            'isSufficientFor100k', (revCapacity >= revPerDay));
    end
end

function aImpact = evaluate_ai_impact(p, targetDaily)
    aImpact = struct();
    aImpact.configuredAiProcessTimeMin = p.aiProcessTimeMin;
    aImpact.dailyCapacity              = p.simTimeMin / p.aiProcessTimeMin;
    aImpact.annualCapacity             = aImpact.dailyCapacity * 365;
    aImpact.utilizationAtTarget        = targetDaily / aImpact.dailyCapacity;
    aImpact.maxAllowedAiTimeMin        = p.simTimeMin / targetDaily;
end

% -------------------------------------------------------------------------
% Scenario summary evaluator
% -------------------------------------------------------------------------
function entry = evaluate_scenario_entry(r, p, targetDaily)
    entry = empty_scenario_summary();
    entry.scenario       = r.scenario;
    entry.bandwidthMbps  = p.bandwidthMbps;
    entry.numReviewers   = p.numReviewers;
    entry.patientsPerDay = p.patientsPerDay;
    entry.executionStatus= r.executionStatus;

    % Analytical bottleneck calculation
    effAcqTime = p.acquisitionTimeMin / (1 - p.recaptureRate);
    cAcq = p.simTimeMin / effAcqTime;
    cNet = (p.simTimeMin * 60) / (p.transmissionDelayS + (p.imageSizeMB * 8 / p.bandwidthMbps));
    cAi  = p.simTimeMin / p.aiProcessTimeMin;
    cRev = (p.numReviewers * (p.simTimeMin / p.reviewTimeMin)) / p.referralRate;

    caps = [cAcq, cNet, cAi, cRev];
    names = {'Acquisition', 'Network', 'AI Server', 'Reviewers'};
    [minCap, idx] = min(caps);

    entry.analyticalBottleneck  = names{idx};
    entry.analyticalMaxDailyCap = minCap;
    entry.analyticalMaxAnnualCap= minCap * 365;

    if strcmp(r.executionStatus, 'SUCCESS') && ~isnan(r.throughput)
        entry.simulatedThroughput = r.throughput;
        entry.simulatedCapacity   = r.annualCapacity;
        entry.simulatedBottleneck = r.bottleneck;
        entry.dataType            = 'SIMULATION_RESULT';
    else
        entry.simulatedThroughput = NaN;
        entry.simulatedCapacity   = NaN;
        entry.simulatedBottleneck = 'PENDING';
        entry.dataType            = 'ANALYTICAL_ESTIMATE';
    end
end

function s = empty_scenario_summary()
    s = struct(...
        'scenario',                '', ...
        'bandwidthMbps',           NaN, ...
        'numReviewers',            NaN, ...
        'patientsPerDay',          NaN, ...
        'executionStatus',         '', ...
        'dataType',                '', ...
        'simulatedThroughput',     NaN, ...
        'simulatedCapacity',       NaN, ...
        'simulatedBottleneck',     '', ...
        'analyticalBottleneck',    '', ...
        'analyticalMaxDailyCap',   NaN, ...
        'analyticalMaxAnnualCap',  NaN);
end

function bn = determine_simulated_bottleneck(results)
    bn = 'None';
    for i = 1:numel(results)
        if ~isempty(results(i).bottleneck) && ~strcmp(results(i).bottleneck, 'PENDING')
            bn = results(i).bottleneck;
            return;
        end
    end
end

% -------------------------------------------------------------------------
% Scalability / what-if analysis for 100,000 patients/year
% -------------------------------------------------------------------------
function sa = compute_scalability_analysis(p, targetDaily, targetAnnual, results)
%COMPUTE_SCALABILITY_ANALYSIS  Determine resource requirements for 100k/yr.
%
%   This is an ANALYTICAL what-if calculation, not a simulation claim.
%   It determines what resources/capacity would be needed to reach the
%   SIH 2026 PS 26038 target of 100,000 patients/year.

    sa = struct();
    sa.targetAnnual = targetAnnual;
    sa.targetDaily  = targetDaily;

    % Current measured throughput (from simulation or analytical)
    hasSimResult = any(strcmp({results.executionStatus}, 'SUCCESS') & ~isnan([results.throughput]));
    if hasSimResult
        baseIdx = find(strcmp({results.scenario}, 'baseline'), 1);
        if ~isempty(baseIdx) && ~isnan(results(baseIdx).throughput)
            sa.currentDailyThroughput = results(baseIdx).throughput;
        else
            sa.currentDailyThroughput = max([results.throughput]);
        end
    else
        % Analytical estimate
        effAcqTime = p.acquisitionTimeMin * 60 / (1 - p.recaptureRate);
        capAcq = (p.simTimeMin * 60) / effAcqTime;
        capNet = (p.simTimeMin * 60) / (p.transmissionDelayS + (p.imageSizeMB * 8 / p.bandwidthMbps));
        capAi  = (p.simTimeMin * 60) / (p.aiProcessTimeMin * 60);
        capRev = (p.numReviewers * (p.simTimeMin * 60 / (p.reviewTimeMin * 60))) / p.referralRate;
        sa.currentDailyThroughput = min([capAcq, capNet, capAi, capRev]);
    end

    sa.currentAnnualCapacity = sa.currentDailyThroughput * 365;
    sa.gapToTarget            = targetAnnual - sa.currentAnnualCapacity;
    sa.scalingFactor          = targetDaily / sa.currentDailyThroughput;
    sa.isTargetAchieved       = sa.currentAnnualCapacity >= targetAnnual;

    % What resources would need to change for 100k/yr
    sa.requiredChanges = {};

    % Acquisition: how many stations needed
    effAcqTime = p.acquisitionTimeMin * 60 / (1 - p.recaptureRate);
    acqDailyCap = (p.simTimeMin * 60) / effAcqTime;
    acqStationsNeeded = ceil(targetDaily / acqDailyCap);
    if acqStationsNeeded > 1
        sa.requiredChanges{end+1} = sprintf( ...
            'Acquisition: %d camera station(s) required (currently 1)', acqStationsNeeded);
    end
    sa.acqStationsNeeded = acqStationsNeeded;

    % Network: minimum bandwidth
    availSecPerPatient = (p.simTimeMin * 60) / targetDaily - p.transmissionDelayS;
    if availSecPerPatient > 0
        minBw = (p.imageSizeMB * 8) / availSecPerPatient;
    else
        minBw = Inf;
    end
    if minBw > p.bandwidthMbps
        sa.requiredChanges{end+1} = sprintf( ...
            'Network: >= %.2f Mbps required (currently %.1f Mbps)', minBw, p.bandwidthMbps);
    end
    sa.minBandwidthRequired = minBw;

    % AI: maximum allowable processing time
    maxAiTime = (p.simTimeMin * 60) / targetDaily;
    if maxAiTime < p.aiProcessTimeMin * 60
        sa.requiredChanges{end+1} = sprintf( ...
            'AI: <= %.1f sec processing time required (currently %.1f sec)', ...
            maxAiTime, p.aiProcessTimeMin * 60);
    end
    sa.maxAiProcessingTimeSec = maxAiTime;

    % Reviewers: minimum count
    reviewsNeededPerDay = targetDaily * p.referralRate;
    revCapacityPerReviewer = (p.simTimeMin * 60) / (p.reviewTimeMin * 60);
    minReviewers = ceil(reviewsNeededPerDay / revCapacityPerReviewer);
    if minReviewers > p.numReviewers
        sa.requiredChanges{end+1} = sprintf( ...
            'Reviewers: %d required (currently %d)', minReviewers, p.numReviewers);
    end
    sa.minReviewersRequired = minReviewers;

    if isempty(sa.requiredChanges)
        sa.requiredChanges{1} = 'No resource changes needed for 100k/yr (analytical)';
    end
end

% -------------------------------------------------------------------------
% Report display
% -------------------------------------------------------------------------
function print_capacity_report(a)
    fprintf('\n%s\n', repmat('=', 1, 95));
    fprintf('           RETINASENSE DISTRICT TELEMEDICINE CAPACITY ANALYSIS\n');
    fprintf('           Target: 100,000 patients/year (~%.1f patients/8h day)\n', a.requiredDailyThroughput);
    fprintf('%s\n', repmat('=', 1, 95));

    fprintf('Simulation Execution Status: %s\n', a.executionStatus);
    fprintf('Annual Target Feasibility:   %s\n', string(a.targetAchieved));
    fprintf('Identified Bottleneck:       %s\n\n', a.bottleneckResource);

    fprintf('--- ANALYTICAL RESOURCE BOUNDS (Theoretical Estimates) ---\n');
    fprintf('1. Acquisition:  1 station = %.0f pts/day (req for 100k: %d station(s))\n', ...
        a.resources.acquisition.singleStationDailyCapacity, a.resources.acquisition.stationsRequiredFor100k);
    fprintf('2. Network:      %.1f Mbps = %.0f pts/day (min req: %.2f Mbps)\n', ...
        a.resources.network.bandwidthMbps, a.resources.network.dailyCapacity, a.resources.network.minBandwidthRequiredMbps);
    fprintf('3. AI Server:    %.1f min/pt = %.0f pts/day (utilization @ 274: %.1f%%)\n', ...
        a.resources.aiProcessing.aiProcessTimeMin, a.resources.aiProcessing.dailyCapacity, a.resources.aiProcessing.utilizationAtTarget * 100);
    fprintf('4. Reviewers:    %d reviewer(s) = %.0f pts/day capacity (min req: %d reviewer(s))\n\n', ...
        a.resources.reviewers.numReviewers, a.resources.reviewers.maxScreenedCapacityDay, a.resources.reviewers.minReviewersRequired);

    fprintf('--- WHAT-IF SCENARIO SUMMARY ---\n');
    fprintf('%-18s | %-7s | %-12s | %-15s | %-20s\n', ...
        'Scenario', 'Status', 'Sim Capacity', 'Analytical Cap', 'Analytical Bottleneck');
    fprintf('%s\n', repmat('-', 1, 95));
    for i = 1:numel(a.scenarios)
        s = a.scenarios(i);
        if isnan(s.simulatedCapacity)
            simCapStr = 'PENDING';
        else
            simCapStr = sprintf('%.0f/yr', s.simulatedCapacity);
        end
        fprintf('%-18s | %-7s | %-12s | %-15s | %-20s\n', ...
            s.scenario, s.executionStatus, simCapStr, ...
            sprintf('%.0f/yr', s.analyticalMaxAnnualCap), s.analyticalBottleneck);
    end
    fprintf('%s\n\n', repmat('=', 1, 95));

    % Scalability analysis section
    sa = a.scalabilityAnalysis;
    fprintf('--- SCALABILITY: 100,000 PATIENTS/YEAR (SIH 2026 PS 26038 TARGET) ---\n');
    fprintf('Current measured capacity:  %.0f patients/year (%.1f/day)\n', ...
        sa.currentAnnualCapacity, sa.currentDailyThroughput);
    fprintf('Target:                     %d patients/year (%.1f/day)\n', ...
        sa.targetAnnual, sa.targetDaily);
    fprintf('Gap to target:              %.0f patients/year\n', sa.gapToTarget);
    fprintf('Scaling factor needed:      %.2fx\n', sa.scalingFactor);
    fprintf('Target achieved (analytical): %s\n', string(sa.isTargetAchieved));
    fprintf('\nRequired resource changes for 100k/yr:\n');
    for i = 1:numel(sa.requiredChanges)
        fprintf('  - %s\n', sa.requiredChanges{i});
    end
    fprintf('\nNOTE: 100,000 patients/year is a SCALABILITY TARGET from the SIH\n');
    fprintf('problem statement. The current prototype measures actual throughput;\n');
    fprintf('the scaling analysis above is an analytical what-if calculation.\n');
    fprintf('%s\n\n', repmat('=', 1, 95));
end

% -------------------------------------------------------------------------
% Error handling
% -------------------------------------------------------------------------
function fail(code, msg, varargin)
    if exist('raiseError', 'file') == 2
        raiseError('analyze_capacity', code, msg, varargin{:});
    else
        id = sprintf('RetinaSense:analyze_capacity:%s', code);
        error(id, msg, varargin{:});
    end
end