function params = scenario_params(scenarioName, overrides)
%SCENARIO_PARAMS  Named inputs for the SimEvents district-scale simulation.
%
%   params = scenario_params()
%   params = scenario_params(scenarioName)
%   params = scenario_params(scenarioName, overrides)
%
%   All named model inputs for simulink/DRTelemedicine.slx live here
%   (docs/ARCHITECTURE.md §7): arrival rate, service times, bandwidth,
%   recapture/referral rates, reviewer count. Edit or select named scenarios
%   to run what-if evaluations.
%
%   Supported scenarios:
%     'baseline'        - District scale: 274 pts/day, 2.0 Mbps, 2 reviewers
%     'low_load'        - Low arrival volume (150 pts/day, mean arrival 3.2 min)
%     'high_load'       - High arrival volume (400 pts/day, mean arrival 1.2 min)
%     'rural_1mbps'     - Constrained 1.0 Mbps rural uplink
%     'rural_4mbps'     - High-speed 4.0 Mbps clinic uplink
%     'solo_reviewer'   - Single ophthalmologist reviewer (bottleneck test)
%     'team_5_reviewers'- 5 parallel ophthalmologist reviewers

    if nargin < 1 || isempty(scenarioName)
        scenarioName = 'baseline';
    end

    % Input validation: scenarioName
    if ~(ischar(scenarioName) || (isstring(scenarioName) && isscalar(scenarioName)))
        fail('InvalidScenarioType', 'scenarioName must be a char vector or string scalar.');
    end
    scenarioName = lower(char(scenarioName));

    validScenarios = {'baseline', 'low_load', 'high_load', ...
                      'rural_1mbps', 'rural_4mbps', ...
                      'solo_reviewer', 'team_5_reviewers'};
    if ~ismember(scenarioName, validScenarios)
        fail('InvalidScenario', ...
            'Unknown scenario "%s". Supported scenarios: %s', ...
            scenarioName, strjoin(validScenarios, ', '));
    end

    params = struct();

    % ---- Baseline district scale assumptions (100k pts/yr ~ 274/day) ----
    params.patientsPerDay     = 274;     % 100000/365
    params.workHoursPerDay    = 8;
    params.meanArrivalTimeMin = 1.75;    % ~274 over 8h Poisson arrivals

    params.acquisitionTimeMin = 3.0;     % capture service time
    params.imageSizeMB        = 8.0;     % per OPD image payload
    params.bandwidthMbps      = 2.0;     % rural link (low/med/high scenarios)
    params.transmissionDelayS = 15;      % fixed + rate-dependent transfer

    params.aiProcessTimeMin   = 1.5;     % AI grading service time
    params.queueCapacity      = 200;     % FIFO queue before AI server

    params.recaptureRate      = 0.10;    % fraction of images sent back for retake
    params.referralRate       = 0.08;    % fraction going to ophthalmologist review
    params.reviewTimeMin      = 5.0;     % review service time
    params.numReviewers       = 2;       % parallel review servers

    params.seed               = 42;      % reproducibility (SimEvents random stream)
    params.simTimeMin         = 480;     % one workday = 8h

    % ---- Apply named scenario modifications ----
    switch scenarioName
        case 'baseline'
            % Keep baseline defaults

        case 'low_load'
            params.patientsPerDay     = 150;
            params.meanArrivalTimeMin = params.simTimeMin / params.patientsPerDay; % 3.2 min

        case 'high_load'
            params.patientsPerDay     = 400;
            params.meanArrivalTimeMin = params.simTimeMin / params.patientsPerDay; % 1.2 min

        case 'rural_1mbps'
            params.bandwidthMbps      = 1.0;

        case 'rural_4mbps'
            params.bandwidthMbps      = 4.0;

        case 'solo_reviewer'
            params.numReviewers       = 1;

        case 'team_5_reviewers'
            params.numReviewers       = 5;
    end

    % ---- Apply optional parameter overrides ----
    if nargin >= 2 && ~isempty(overrides)
        if ~isstruct(overrides)
            fail('InvalidInput', 'overrides must be a struct.');
        end
        fn = fieldnames(overrides);
        for i = 1:numel(fn)
            if isfield(params, fn{i})
                params.(fn{i}) = overrides.(fn{i});
            else
                fail('UnknownParameter', 'Unknown parameter override: %s', fn{i});
            end
        end
    end

    % ---- Validate parameter values ----
    validate_params(params);
end

function validate_params(p)
    fields = {'patientsPerDay', 'workHoursPerDay', 'meanArrivalTimeMin', ...
              'acquisitionTimeMin', 'imageSizeMB', 'bandwidthMbps', ...
              'transmissionDelayS', 'aiProcessTimeMin', 'queueCapacity', ...
              'recaptureRate', 'referralRate', 'reviewTimeMin', ...
              'numReviewers', 'seed', 'simTimeMin'};
    for i = 1:numel(fields)
        if ~isfield(p, fields{i})
            fail('MissingField', 'Missing required parameter field: %s', fields{i});
        end
    end

    if ~(isnumeric(p.patientsPerDay) && isscalar(p.patientsPerDay) && isfinite(p.patientsPerDay) && p.patientsPerDay > 0)
        fail('InvalidParam', 'patientsPerDay must be a positive numeric scalar.');
    end
    if ~(isnumeric(p.workHoursPerDay) && isscalar(p.workHoursPerDay) && isfinite(p.workHoursPerDay) && p.workHoursPerDay > 0 && p.workHoursPerDay <= 24)
        fail('InvalidParam', 'workHoursPerDay must be a positive numeric scalar <= 24.');
    end
    if ~(isnumeric(p.meanArrivalTimeMin) && isscalar(p.meanArrivalTimeMin) && isfinite(p.meanArrivalTimeMin) && p.meanArrivalTimeMin > 0)
        fail('InvalidParam', 'meanArrivalTimeMin must be a positive numeric scalar.');
    end
    if ~(isnumeric(p.acquisitionTimeMin) && isscalar(p.acquisitionTimeMin) && isfinite(p.acquisitionTimeMin) && p.acquisitionTimeMin > 0)
        fail('InvalidParam', 'acquisitionTimeMin must be a positive numeric scalar.');
    end
    if ~(isnumeric(p.imageSizeMB) && isscalar(p.imageSizeMB) && isfinite(p.imageSizeMB) && p.imageSizeMB > 0)
        fail('InvalidParam', 'imageSizeMB must be a positive numeric scalar.');
    end
    if ~(isnumeric(p.bandwidthMbps) && isscalar(p.bandwidthMbps) && isfinite(p.bandwidthMbps) && p.bandwidthMbps > 0)
        fail('InvalidParam', 'bandwidthMbps must be a positive numeric scalar.');
    end
    if ~(isnumeric(p.transmissionDelayS) && isscalar(p.transmissionDelayS) && isfinite(p.transmissionDelayS) && p.transmissionDelayS >= 0)
        fail('InvalidParam', 'transmissionDelayS must be a non-negative numeric scalar.');
    end
    if ~(isnumeric(p.aiProcessTimeMin) && isscalar(p.aiProcessTimeMin) && isfinite(p.aiProcessTimeMin) && p.aiProcessTimeMin > 0)
        fail('InvalidParam', 'aiProcessTimeMin must be a positive numeric scalar.');
    end
    if ~(isnumeric(p.queueCapacity) && isscalar(p.queueCapacity) && isfinite(p.queueCapacity) && p.queueCapacity >= 1 && floor(p.queueCapacity) == p.queueCapacity)
        fail('InvalidParam', 'queueCapacity must be a positive integer scalar >= 1.');
    end
    if ~(isnumeric(p.recaptureRate) && isscalar(p.recaptureRate) && isfinite(p.recaptureRate) && p.recaptureRate >= 0 && p.recaptureRate < 1)
        fail('InvalidParam', 'recaptureRate must be a numeric scalar in [0, 1).');
    end
    if ~(isnumeric(p.referralRate) && isscalar(p.referralRate) && isfinite(p.referralRate) && p.referralRate >= 0 && p.referralRate <= 1)
        fail('InvalidParam', 'referralRate must be a numeric scalar in [0, 1].');
    end
    if ~(isnumeric(p.reviewTimeMin) && isscalar(p.reviewTimeMin) && isfinite(p.reviewTimeMin) && p.reviewTimeMin > 0)
        fail('InvalidParam', 'reviewTimeMin must be a positive numeric scalar.');
    end
    if ~(isnumeric(p.numReviewers) && isscalar(p.numReviewers) && isfinite(p.numReviewers) && p.numReviewers >= 1 && floor(p.numReviewers) == p.numReviewers)
        fail('InvalidParam', 'numReviewers must be a positive integer scalar >= 1.');
    end
    if ~(isnumeric(p.seed) && isscalar(p.seed) && isfinite(p.seed) && p.seed >= 0 && floor(p.seed) == p.seed)
        fail('InvalidParam', 'seed must be a non-negative integer scalar.');
    end
    if ~(isnumeric(p.simTimeMin) && isscalar(p.simTimeMin) && isfinite(p.simTimeMin) && p.simTimeMin > 0)
        fail('InvalidParam', 'simTimeMin must be a positive numeric scalar.');
    end
end

function fail(code, msg, varargin)
    if exist('raiseError', 'file') == 2
        raiseError('scenario_params', code, msg, varargin{:});
    else
        id = sprintf('RetinaSense:scenario_params:%s', code);
        error(id, msg, varargin{:});
    end
end