function T = loadCalibration(cfg)
%LOADCALIBRATION  Load the fitted calibration temperature T (§3.7 / §8).
%
%   T = loadCalibration(cfg)
%
%   Loads T persisted by calibration/saveCalibration.m as
%
%       data/models/<backbone>_calib.mat       (paths().data.models)
%
%   where <backbone> = cfg.model.backbone (benchmark-driven). Returns the
%   fitted temperature for calibration/applyCalibration.m.
%
%   Callers gate on cfg.model.available (scripts/runPipeline.m does); this
%   loader still validates the artifact file so the pipeline fails with a
%   clear structured error instead of silently using the identity T=1 when a
%   real calibration artifact was expected.
%
%   Failures (AGENTS.md raiseError convention):
%     RetinaSense:loadCalibration:MissingModel     no backbone selected
%     RetinaSense:loadCalibration:MissingArtifact  artifact file does not exist
%     RetinaSense:loadCalibration:InvalidArtifact  unreadable / no T variable
%     RetinaSense:loadCalibration:InvalidTemperature T not a positive finite scalar

    validateattributes(cfg, {'struct'}, {'scalar'}, 'loadCalibration', 'cfg', 1);

    backbone = cfg.model.backbone;
    if isempty(backbone)
        raiseError('loadCalibration', 'MissingModel', ...
            'No backbone selected (cfg.model.backbone is empty). Run benchmark_backbones first.');
    end

    artFile = fullfile(paths().data.models, sprintf('%s_calib.mat', backbone));
    if ~exist(artFile, 'file')
        raiseError('loadCalibration', 'MissingArtifact', ...
            'Calibration artifact not found: %s', artFile);
    end

    try
        S = load(artFile);
    catch ME
        raiseError('loadCalibration', 'InvalidArtifact', ...
            'Failed to load calibration artifact %s: %s', artFile, ME.message);
    end

    if ~isfield(S, 'T')
        raiseError('loadCalibration', 'InvalidArtifact', ...
            'Calibration artifact %s does not contain variable ''T''.', artFile);
    end

    T = S.T;
    if ~isnumeric(T) || ~isscalar(T) || ~isfinite(T) || T <= 0
        raiseError('loadCalibration', 'InvalidTemperature', ...
            'Calibration artifact %s contains invalid T=%s.', artFile, mat2str(T));
    end
end