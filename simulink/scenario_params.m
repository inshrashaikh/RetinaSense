function params = scenario_params()
%SCENARIO_PARAMS  Named inputs for the SimEvents district-scale simulation.
%
%   params = scenario_params()
%
%   All named model inputs for simulink/DRTelemedicine.slx live here
%   (docs/ARCHITECTURE.md §7): arrival rate, service times, bandwidth,
%   recapture/referral rates, reviewer count. Edit to run what-if scenarios.

    params = struct();

    % District scale assumptions for the 100k patients/yr check (~274/day).
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
end