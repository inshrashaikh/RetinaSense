function run_simulink_scenarios()
%RUN_SIMULINK_SCENARIOS  Drive DRTelemedicine.slx what-if scenarios.
%
%   Runs low/high load, rural bandwidth (1/2/4 Mbps), reviewer counts (1/2/5),
%   tabulates throughput/wait/queue/utilization and checks whether the
%   100,000 patients/yr (~274/day) target is achievable per scenario.
%   (docs/ARCHITECTURE.md §7.)
%
%   TODO(Sprint 6): requires simulink/DRTelemedicine.slx (SimEvents model).
%   The annual-capacity claim is made only after the model demonstrates it.

    if exist('DRTelemedicine.slx', 'file') ~= 2
        raiseError('run_simulink_scenarios', 'MissingModel', ...
            'simulink/DRTelemedicine.slx does not exist yet (Sprint 6 task).');
    end
    raiseError('run_simulink_scenarios', 'NotImplemented', ...
        'Scenario driver is a Sprint 6 task (needs the SimEvents model).');
end