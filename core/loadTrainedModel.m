function net = loadTrainedModel(cfg)
%LOADTRAINEDMODEL  Load the trained DR grading network artifact (§3.2 / §8).
%
%   net = loadTrainedModel(cfg)
%
%   Loads the network persisted by classification/trainClassifier.m /
%   scripts/benchmark_backbones.m as
%
%       data/models/<backbone>_dr_aptos.mat       (paths().data.models)
%
%   where <backbone> = cfg.model.backbone (benchmark-driven). Returns the
%   trained network handle (dlnetwork / SeriesNetwork / DAGNetwork) for
%   classification/classifyImage.m and explainability/computeGradCAM.m.
%
%   Callers gate on cfg.model.available (scripts/runPipeline.m does); this
%   loader still validates the artifact file so the pipeline fails with a
%   clear structured error instead of silently falling back to the
%   mock.
%
%   Failures (AGENTS.md raiseError convention):
%     RetinaSense:loadTrainedModel:MissingModel     no backbone selected
%     RetinaSense:loadTrainedModel:MissingArtifact  artifact file does not exist
%     RetinaSense:loadTrainedModel:InvalidArtifact  file unreadable / no net
%
%   Returned net is ONLY usable with the Deep Learning Toolbox; without the
%   toolbox the callers' own honest fallbacks apply (never fabricated output).

    validateattributes(cfg, {'struct'}, {'scalar'}, 'loadTrainedModel', 'cfg', 1);

    backbone = cfg.model.backbone;
    if isempty(backbone)
        raiseError('loadTrainedModel', 'MissingModel', ...
            'No backbone selected (cfg.model.backbone is empty). Run benchmark_backbones first.');
    end

    artFile = fullfile(paths().data.models, sprintf('%s_dr_aptos.mat', backbone));
    if ~exist(artFile, 'file')
        raiseError('loadTrainedModel', 'MissingArtifact', ...
            'Trained artifact not found: %s', artFile);
    end

    try
        S = load(artFile);
    catch ME
        raiseError('loadTrainedModel', 'InvalidArtifact', ...
            'Failed to load artifact %s: %s', artFile, ME.message);
    end

    net = extractNet(S);
    if isempty(net)
        raiseError('loadTrainedModel', 'InvalidArtifact', ...
            'Artifact %s does not contain a usable network (expected variable ''net'').', artFile);
    end
end

function net = extractNet(S)
%EXTRACTNET  Pull the network object out of a loaded artifact struct.
% Tolerates the documented variable name 'net'; also accepts a file whose
% single/any variable is a network object (robust to alternate save layouts).
    if isfield(S, 'net')
        net = S.net;
        if isObjectNet(net); return; end
    end
    names = fieldnames(S);
    for i = 1:numel(names)
        v = S.(names{i});
        if isObjectNet(v)
            net = v; return;
        end
    end
    net = [];
end

function tf = isObjectNet(v)
%ISOBJECTNET  A usable network is a trained DL-net object (not a struct/lgraph).
    tf = isa(v, 'dlnetwork') || isa(v, 'SeriesNetwork') || isa(v, 'DAGNetwork');
end