function filepath = saveCalibration(T, backbone)
%SAVECALIBRATION  Persist the fitted calibration temperature T (§3.7 / §8).
%
%   filepath = saveCalibration(T, backbone)
%
%   Writes data/models/<backbone>_calib.mat (paths().data.models) containing
%   T as fitted by calibration/fitTemperature.m on VALIDATION logits, so that
%   scripts/runPipeline.m can load and apply it with a trained model (never an
%   identity T=1 fallback when a real calibration artifact exists).
%
%   Validation (AGENTS.md raiseError convention):
%     RetinaSense:saveCalibration:MissingBackbone    backbone name empty
%     RetinaSense:saveCalibration:InvalidTemperature T not a positive finite scalar
%
%   Honesty: an unfitted/empty T (no validation split) is NEVER persisted;
%   callers skip this function in that case instead of storing a fake T.

    if nargin < 2 || isempty(backbone)
        raiseError('saveCalibration', 'MissingBackbone', ...
            'saveCalibration needs the backbone name to name the artifact.');
    end

    if ~isnumeric(T) || ~isscalar(T) || ~isfinite(T) || T <= 0
        raiseError('saveCalibration', 'InvalidTemperature', ...
            'Cannot persist T=%s; temperature must be a positive finite scalar.', ...
            mat2str(T));
    end

    filepath = fullfile(paths().data.models, sprintf('%s_calib.mat', backbone));
    save(filepath, 'T');
end