function c = newCase()
%NEWCASE  Construct an empty-but-valid RetinaSense Case struct.
%
%   c = newCase()
%
%   Returns a Case struct with every field defined ([] or NaN where not yet
%   populated). This is the shared, deterministic data structure that flows
%   through runPipeline and every module contract (docs/ARCHITECTURE.md §4).
%
%   Fields are populated stage-by-stage; the orchestrator (scripts/runPipeline.m)
%   wires the stages in order. Module contracts MUST read/write only these
%   fields so integration stays deterministic and unit-testable.
%
%   No module should construct a Case from scratch — always call newCase()
%   (or mutate the case passed in).

    c = struct();

    % ---- Stage 0: Ingestion (preprocessing/ingestImage.m) ----
    c.image        = [];   % HxWx3 uint8 working RGB image (downscaled)
    c.imagePath    = '';   % original file path (if any)
    c.meta         = struct( ...
        'patientId', '', ...   % opaque token, no PII beyond this
        'eye',       '', ...   % 'left' | 'right'
        'timestamp', '', ...   % ISO-8601 string
        'phcId',     '');      % primary health centre id

    % ---- Stage 1: Image Quality Assessment (preprocessing/assessQuality.m) ----
    c.quality = struct( ...
        'score',          NaN, ...           % double 0..1 overall
        'class',          '', ...            % 'good' | 'borderline' | 'ungradable'
        'metrics',        struct(...         % per-metric scores 0..1
                                'focus', NaN, ...
                                'illumination', NaN, ...
                                'fovCoverage', NaN, ...
                                'artifacts', NaN), ...
        'failureReasons', {{}}, ...          % cellstr, e.g. {'focus'}
        'recapture',      struct(...         % set only if ungradable
                                'reasonCode', '', ...
                                'instruction', ''));

    % ---- Stage 3/4: Enhancement (preprocessing/enhanceImage.m / recheckQuality.m) ----
    c.enhancement = struct( ...
        'appliedOps',        {{}}, ...   % cellstr {'clahe','illumNorm','denoise'}
        'paramsPerOp',       struct(), ...% per-op parameters
        'improved',          false, ...  % bool: enhanced re-score improved
        'recheckClass',      '');        % class after recheck ('good'|'borderline'|'ungradable')

    % ---- Stage 5: Retinal / Lesion Analysis (analysis/*) ADVISORY ----
    c.evidence = struct( ...
        'vesselMask', [], ...            % logical HxW
        'opticDisc',  [], ...            % [x,y]
        'fovea',      [], ...            % [x,y]
        'lesions',    struct(...         % per-class
                           'exudates', struct('map',[], 'count',NaN, 'features',[]), ...
                           'hemorrhages', struct('map',[], 'count',NaN, 'features',[]), ...
                           'microaneurysms', struct('map',[], 'count',NaN, 'features',[]), ...
                           'neoVasc', struct('map',[], 'count',NaN, 'features',[])), ...
        'confidence', '');               % 'low' | 'medium' | 'high' (advisory)

    % ---- Stage 6: DR Grading (classification/classifyImage.m) ----
    c.grading = struct( ...
        'rawProbs',      NaN(1,5), ...       % P(grade 0..4), sums to 1
        'grade',         NaN, ...            % 0..4 (argmax)
        'referableProb', NaN, ...            % P(grade>=2)
        'referable',     false, ...          % referableProb >= referThreshold(config)
        'modelFile',     '');                % which trained net was used ('' in mock)

    % ---- Stage 7: Explainability (explainability/computeGradCAM.m) ----
    c.explain = struct( ...
        'gradCam',         [], ...   % HxWx1 double normalized attention heatmap
        'attentionImage',  [], ...   % HxWx3 uint8 overlay
        'evidenceOverlay', [], ...   % HxWx3 uint8 lesion candidates overlay
        'note', '');                 % 'Model attention - not proof of causality'

    % ---- Stage 8: Calibration (calibration/applyCalibration.m) ----
    c.calibrated = struct( ...
        'calibratedProbs', NaN(1,5), ... % temperature-scaled, sums to 1
        'confidence',      NaN, ...      % max(calibratedProbs) 0..1
        'uncertainty',     NaN, ...      % normalized entropy 0..1
        'reviewRequired',  false);       % true if below/above thresholds or forced

    % ---- Stage 9: Human Review (reporting/submitReview.m) ----
    c.review = struct( ...
        'action',        '', ...   % 'approve' | 'override' | 'recapture' | 'auto'
        'graderId',      '', ...
        'overrideGrade', NaN, ...  % 0..4 or NaN
        'finalReferral', false, ...
        'status',        '', ...   % 'auto' | 'approved' | 'overridden'
        'notes',         '');

    % ---- Stage 9: Report (reporting/buildReport.m) ----
    c.report = struct( ...
        'data',     struct(), ...  % structured machine-readable subset
        'summary',  '', ...        % concise paragraph
        'filepath', '', ...        % rendered report path ('' in mock unless render)
        'review',   struct());     % embedded final review/decision

    % ---- Pipeline bookkeeping ----
    c.pipeline = struct( ...
        'stages',        {{}}, ...   % ordered list of stage names executed
        'startedAt',     '', ...     % ISO-8601
        'finishedAt',    '', ...     % ISO-8601
        'enhanced',      false, ...  % true if enhancement+recheck path taken
        'exitStage',     '');        % where pipeline exited ('' = normal end)

    % ---- Model availability (set by runPipeline at startup) ----
    c.model = struct( ...
        'backbone',  '', ...  % chosen backbone name ('' in mock; set by benchmark)
        'available', false);  % true only when a real trained net is present
end
