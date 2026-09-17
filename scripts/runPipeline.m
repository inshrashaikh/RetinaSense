function c = runPipeline(varargin)
%RUNPIPELINE  RetinaSense main entry / pipeline orchestrator (CLI).
%
%   c = runPipeline()                          % run a default real screening case
%   c = runPipeline(meta, imagePath)           % single ingestion entry (§1)
%   c = runPipeline(meta, imagePath, reviewerInput)
%   c = runPipeline(caseIn)                    % continue from an existing case
%
%   Name-value options (first arg parsed if a string):
%     'scenario', 'good'|'borderline'|'ungradable'   force a scenario (tests/demo)
%     'mock', true|false                             enable/disable mock modules
%
%   Screening defaults to the real trained model ('mock' defaults to false);
%   mock runs only when explicitly requested via 'mock', true (tests/demo).
%   Missing benchmark/model artifacts raise structured errors: no silent
%   fallback to mock.
%
%   Wires the stages in order (docs/ARCHITECTURE.md §2):
%     Image -> Quality Gate -> Enhancement(borderline) -> Re-check
%     -> Retinal/Lesion Analysis + DR Grading
%     -> Explainability + Confidence
%     -> Human Review
%     -> Report
%
%   Every module emits/reads the shared Case (§4). Aggregating exceptions with
%   structured RetinaSense identifiers so callers branch deterministically.
%
%   Returns the fully populated Case (or exits early at the gate for
%   ungradable images with recapture feedback).

    % ---------- Parse entry ----------
    opts = parseArgs(varargin);
    cfg  = experiment_config();

    if ~opts.mock && ~cfg.model.available
        raiseError('runPipeline', 'MissingModel', ...
            'No trained model selected. Run scripts/benchmark_backbones.m to choose a backbone, or pass ''mock'', true for the labelled test/demo path.');
    end

    % ---------- Ingest ----------
    if isstruct(opts.in) && isfield(opts.in, 'image') && ~isempty(opts.in.image)
        c = opts.in;                 % continue-mode: case already has a working image
    else
        meta = opts.meta;
        c = ingestImage(meta, opts.imagePath);
    end

    c.pipeline.startedAt  = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    c.pipeline.stages     = {};
    c.pipeline.enhanced   = false;
    c.pipeline.exitStage  = '';
    c = addStage(c, 'ingest');

    c = applyScenario(c, opts, cfg);

    try
        % ---------- Stage 1: Quality gate ----------
        c.quality = assessQuality(c.image, cfg.quality);
        c = addStage(c, 'qualityGate');

        if strcmp(c.quality.class, 'ungradable')
            % Recapture feedback is already in c.quality.recapture.
            c.pipeline.exitStage = 'qualityGate';
            logMessage('info', 'PIPELINE', ...
                sprintf('Image ungradable -> recapture (%s)', c.quality.recapture.reasonCode));
            return;
        end

        % ---------- Stage 3-4: Enhancement if borderline ----------
        if strcmp(c.quality.class, 'borderline')
            [imgEnh, enhMeta] = enhanceImage(c.image, c.quality, cfg.preprocess.enhance);
            [ok, recheck, enhMeta] = recheckQuality(imgEnh, enhMeta, c.quality.score);
            c.pipeline.enhanced = ok;
            c.enhancement.appliedOps  = enhMeta.appliedOps;
            c.enhancement.paramsPerOp = enhMeta.paramsPerOp;
            c.enhancement.improved    = enhMeta.improved;
            c.enhancement.recheckClass = enhMeta.recheckClass;
            if ok
                c.image = imgEnh;
                % Keep the gate's routing class on the case: the routed image
                % WAS 'borderline' and took the Stage 3-4 enhancement path.
                % The post-enhancement recheck outcome lives in
                % c.enhancement.recheckClass / c.enhancement.improved, so
                % c.quality always describes the ROUTED (pre-enhancement)
                % image and never over-claims the enhanced pixels.
            else
                c.quality.recapture = recheck.recapture;
                c.pipeline.exitStage = 'enhancementRecheck';
                logMessage('info', 'PIPELINE', ...
                    'Enhanced image still ungradable -> recapture');
                return;
            end
            c = addStage(c, 'enhancement');
        end

        % ---------- Stage 5: Retinal/Lesion analysis (ADVISORY, non-blocking) ----------
        try
            analysisParams = cfg.analysis;
            analysisParams.eye = c.meta.eye;  % pass eye orientation
            c.evidence = analyzeRetina(c.image, [], analysisParams);
            c = addStage(c, 'analysis');
        catch ME
            % Advisory: never blocks grading. Log and continue with no evidence.
            logMessage('warn', 'PIPELINE', ...
              sprintf('Analysis advisory module skipped (non-blocking): %s', ME.message));
            c.evidence = struct( ...  % minimal valid evidence
                'vesselMask', [], ...
                'opticDisc', [], 'fovea', [], ...
                'lesions', struct('exudates',struct('map',false(size(c.image,1),size(c.image,2)),'count',0,'features',zeros(4,0)), ...
                                  'hemorrhages',struct('map',false(size(c.image,1),size(c.image,2)),'count',0,'features',zeros(4,0)), ...
                                  'microaneurysms',struct('map',false(size(c.image,1),size(c.image,2)),'count',0,'features',zeros(4,0)), ...
                                  'neoVasc',struct('map',false(size(c.image,1),size(c.image,2)),'count',0,'features',zeros(4,0))), ...
                'confidence', 'low', ...
                'opticDiscDetail', struct('center', [], 'bbox', [], 'confidence', 0, ...
                    'status', 'not_detected', 'method', '', 'note', 'Analysis module failed'));
        end

        % ---------- Stage 6: DR grading ----------
        % Default (mock=false) loads the real trained artifact (gated by
        % cfg.model.available above) and uses it for BOTH grading and
        % Grad-CAM, so real models reach every consumer exactly once per
        % case. mock=true keeps net=[] and classifyImage uses its honest
        % mock path (labelled test/demo only).
        net = [];
        if ~opts.mock
            net = loadTrainedModel(cfg);
            logMessage('info', 'PIPELINE', ...
                sprintf('Loaded trained model: %s_dr_aptos.mat', cfg.model.backbone));
        end
        c.grading = classifyImage(c.image, net, cfg.classification);
        c = addStage(c, 'grading');

        % ---------- Stage 7: Explainability ----------
        c.explain = computeGradCAM(c.image, net, c.grading, c.evidence, cfg.explainability);
        c = addStage(c, 'explainability');

        % ---------- Stage 8: Calibration + confidence/uncertainty ----------
        % Default (mock=false) loads the matching fitted temperature and
        % applies it — never identity when a real calibration artifact
        % exists; a missing/invalid artifact raises a structured
        % loadCalibration error. mock=true keeps T=[] (identity, labelled
        % test/demo only).
        T = [];
        if ~opts.mock
            T = loadCalibration(cfg);
            logMessage('info', 'PIPELINE', ...
                sprintf('Loaded calibration T=%.3f (%s_calib.mat)', T, cfg.model.backbone));
        end
        c.calibrated = applyCalibration(c.grading, T, cfg.calibration);
        c = addStage(c, 'calibration');

        % ---------- Stage 9a: Human review ----------
        reviewInput = opts.reviewerInput;
        if isempty(reviewInput) && c.calibrated.reviewRequired
            % No reviewer present but policy demands review: route to review
            % queue (App UI in Sprint 5). Mock: record as pending review queue,
            % finalReferral carries the AI signal pending ophthalmologist action.
            c.review = struct('action', '', 'graderId', '', 'overrideGrade', NaN, ...
                'finalReferral', c.grading.referable, 'status', 'reqReview', ...
                'notes', 'Low confidence / high uncertainty - routed to ophthalmologist review (FR-08).');
        else
            c.review = submitReview(c, reviewInput);
        end
        c = addStage(c, 'review');

        % ---------- Stage 9b: Report ----------
        c.report = buildReport(c, cfg);
        c.report.filepath = renderReport(c.report, struct('out', paths().output));
        c = addStage(c, 'report');

        c.pipeline.finishedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        logMessage('info', 'PIPELINE', ...
            sprintf('Case %s done: grade %d, referable=%d, review=%s, report=%s', ...
            c.meta.patientId, c.grading.grade, c.grading.referable, ...
            c.review.action, c.report.filepath));

    catch ME
        % Structured error: rethrow with stage context attached.
        c.pipeline.finishedAt = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        logMessage('error', 'PIPELINE', ME.message);
        if strncmp(ME.identifier, 'RetinaSense:', 12)
            rethrow(ME);
        else
            % Wrap unexpected (non-RetinaSense) errors for upstream callers.
            raiseError('runPipeline', 'Unexpected', '%s', ME.message);
        end
    end
end

% --------------------------------------------------------------------------
function c = applyScenario(c, opts, cfg)
    % Force a mock outcome for demos/tests. Mutates the working image only.
    % This is test/demo tooling; never reachable in a real deployment path.
    % Brightness arithmetic is done in 0..1 BEFORE im2uint8: passing a 0..255
    % double straight to im2uint8() re-normalizes it (values >1 clip to 255),
    % which whitens the frame instead of darkening it.
    %
    % 'borderline' under-exposes (illumination into the mid band -> borderline
    % gate, exercising the enhancement branch); 'ungradable' forces a near-
    % black frame; 'good' keeps the strongest-fidelity frame.
    if isempty(opts.scenario); return; end
    imd = double(c.image) / 255;
    switch opts.scenario
        case 'ungradable'
            c.image = im2uint8(max(0, imd * 0.04));   % near-black: fail illum/FOV/focus
        case 'borderline'
            c.image = im2uint8(max(0, imd - 0.18));   % under-exposed: illum into the mid band -> borderline gate
        case 'good'
            % unchanged (see note above)
    end
end

function opts = parseArgs(args)
    opts = struct('in', [], 'meta', struct('patientId','demo001','eye','right', ...
               'timestamp', datestr(now,'yyyy-mm-ddTHH:MM:SS'), 'phcId','PHC-TEST'), ...
               'imagePath', '', 'reviewerInput', [], 'mock', false, 'scenario', '');

    if isempty(args); return; end

    % A positional struct with an 'image' field is a Case to continue.
    % (meta structs have no 'image' field and are treated as metadata.)
    if isstruct(args{1}) && isfield(args{1}, 'image')
        opts.in = args{1};
        args(1) = [];
    end

    i = 1;
    while i <= numel(args)
        a = args{i};
        if (ischar(a) || isstring(a)) && isOption(a)
            key = lower(char(a));
            switch key
                case 'scenario'
                    opts.scenario = validatestring(char(args{i+1}), ...
                        {'good','borderline','ungradable'});
                case 'mock'
                    opts.mock = logical(args{i+1});
                case 'meta';     opts.meta = args{i+1};
                case 'timer';    opts.meta.timestamp = args{i+1};
                case 'image';    opts.imagePath = args{i+1};
                case 'reviewer'; opts.reviewerInput = args{i+1};
            end
            i = i + 2;
        elseif (ischar(a) || isstring(a))
            % Positional filename: runPipeline(meta, imagePath)
            opts.imagePath = char(a);
            i = i + 1;
        elseif isstruct(a) && isfield(a, 'patientId')
            % Positional meta struct: runPipeline(meta, imagePath)
            opts.meta = a;
            i = i + 1;
        elseif isstruct(a) && isfield(a, 'action')
            % Positional reviewer input: runPipeline(meta, imagePath, reviewerInput)
            opts.reviewerInput = a;
            i = i + 1;
        else
            raiseError('runPipeline', 'BadArgs', 'Unrecognized pipeline argument.');
        end
    end
end

function tf = isOption(a)
    tf = any(strcmp(lower(char(a)), ...
        {'scenario','mock','meta','timer','image','reviewer'}));
end

function c = addStage(c, name)
    c.pipeline.stages{end+1} = name;
end