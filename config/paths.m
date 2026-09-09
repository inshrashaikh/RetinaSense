function cfg = paths()
%PATHS  Root filesystem configuration for RetinaSense (config/paths.m).
%
%   cfg = paths()
%
%   Central place for data / model / output root directories and log settings.
%   No paths are hard-coded elsewhere; modules read them here. Edit for your
%   local machine. data/raw and data/processed are gitignored (biomedical
%   licensing — see README).
%
%   This function computes paths relative to the repository root so the repo
%   is relocatable. Change only ABSROOT or the per-env override below.

    % Repository root: parent of the config/ folder.
    root = fileparts(fileparts(mfilename('fullpath')));

    cfg = struct();
    cfg.root   = root;
    cfg.config = fullfile(root, 'config');
    cfg.data   = struct(...
        'root',      fullfile(root, 'data'), ...
        'raw',       fullfile(root, 'data', 'raw'), ...   % gitignored (APTOS, IDRiD, DRIVE, Messidor-2)
        'processed', fullfile(root, 'data', 'processed'), ... % gitignored
        'manifests', fullfile(root, 'data', 'manifests'), ... % committed
        'models',    fullfile(root, 'data', 'models'));   % gitignored .mat
    cfg.output = fullfile(root, 'output');                % reports, plots, metrics
    cfg.assets = fullfile(root, 'assets');                % demo images (gitignored if large)

    % Logging sink. Set log.file = '' to disable file logging (stdout only).
    cfg.log = struct('file', fullfile(root, 'output', 'retinaSense.log'));

    % Ensure required directories exist (harmless; creates on first run).
    dirs = {cfg.data.raw, cfg.data.processed, cfg.data.manifests, ...
            cfg.data.models, cfg.output};
    for i = 1:numel(dirs)
        if ~exist(dirs{i}, 'dir')
            mkdir(dirs{i});
        end
    end
end
