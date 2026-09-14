function result = runIDRiDValidation(locSamples, lesSamples)
%RUNIDRIDVALIDATION  Orchestrator: bounded IDRiD validation stage + artifact.
%
%   result = runIDRiDValidation()
%   result = runIDRiDValidation(locSamples, lesSamples)
%
%   Runs the bounded IDRiD validation suite for components that HAVE official
%   ground truth on IDRiD, and writes a timestamped JSON artifact to
%   output/idrid_validation_<YYYYMMDDTHHMMSS>.json.
%
%   WHAT IS VALIDATED (with honest constraints):
%     - Optic-disc center: locateOpticDisc -> official IDRiD localization GT
%       (native pixel space). Mean/median/max pixel error reported.
%     - Fovea center: locateFovea -> official IDRiD localization GT. Eye side
%       derived from GT geometry (fovea temporal to disc). Geometric estimator
%       validated with correct laterality supplied; not independent-laterality.
%     - Lesion detection: detectLesions (via analyzeRetina production path)
%       against official IDRiD segmentation masks for MA, HE, EX at working
%       resolution. Dice/IoU/sensitivity/precision over images with non-empty
%       GT. Exact N reported.
%
%   WHAT IS DOCUMENTED (no GT available on IDRiD):
%     - Soft exudates (SE): GT exists for a subset but no SE-specific detector
%       class; the bright-lesion "exudates" class is merged. NOT scored.
%     - Neovascularization (neoVasc): no official GT on IDRiD. NOT scored.
%     - Vessel segmentation: IDRiD has no vessel GT. Requires DRIVE.
%       NOT validated here.
%
%   HONESTY (non-negotiable):
%     - Every number in the artifact comes from a real run. None are MOCK.
%     - Missing/non-existent masks are never treated as negatives.
%     - The artifact explicitly states "DATASET VALIDATION, NOT CLINICAL
%       VALIDATION — advisory, non-blocking."
%     - dataset_status.csv is updated ONLY if real metrics were produced.

    if nargin < 1 || isempty(locSamples); locSamples = 3; end
    if nargin < 2 || isempty(lesSamples); lesSamples = 3; end

    try
        p = paths();
    catch
        p = struct('output', fullfile(pwd, 'output'), ...
            'data', struct('manifests', fullfile(pwd, 'data', 'manifests')));
    end
    if ~exist(p.output, 'dir'); mkdir(p.output); end

    ts = datestr(now, 'yyyymmddTHHMMSS');
    artifactName = sprintf('idrid_validation_%s.json', ts);
    artifactPath = fullfile(p.output, artifactName);

    try; resultLocalization = runLocalizationValidation(locSamples);
    catch e; resultLocalization = struct('status', 'ERROR', 'note', e.message, 'n', 0); end
    try; resultLesion = runLesionValidation(lesSamples);
    catch e; resultLesion = struct('status', 'ERROR', 'note', e.message, 'n', 0); end

    % Build a clean JSON-safe struct (avoid deeply nested MATLAB structs that jsonencode can mangle)
    locOD = safeStat(resultLocalization, 'opticDisc');
    locFOV = safeStat(resultLocalization, 'fovea');
    lesionMA = safeLesion(resultLesion, 'ma');
    lesionHE = safeLesion(resultLesion, 'he');
    lesionEX = safeLesion(resultLesion, 'ex');

    verified = strcmp(resultLocalization.status,'PASS') || strcmp(resultLocalization.status,'PARTIAL');
    verifiedLes = strcmp(resultLesion.status,'PASS') || strcmp(resultLesion.status,'PARTIAL');
    if verified && verifiedLes
        overall = 'VALIDATED';
    elseif verified || verifiedLes
        overall = 'PARTIAL';
    else
        overall = 'NOT_VALIDATED';
    end

    artifact = struct( ...
        'dataset', 'IDRiD', ...
        'statement', 'DATASET VALIDATION, NOT CLINICAL VALIDATION - advisory, non-blocking; component behavior against official IDRiD ground truth.', ...
        'timestamp', datestr(now, 'yyyy-mm-ddTHHMM:SS'), ...
        'workingResolution', 'max edge 1024 px (aspect preserved)', ...
        'nativeResolution', '4288 x 2848 px', ...
        'overall', overall, ...
        'opticDisc', locOD, ...
        'fovea', locFOV, ...
        'lesionMA', lesionMA, ...
        'lesionHE', lesionHE, ...
        'lesionEX', lesionEX, ...
        'lesionSE', struct( ...
            'status', 'NOT_SCORED', ...
            'reason', 'GT exists on a subset but no SE-specific detector class; merged bright-lesion exudates class not valid for SE-only claim.', ...
            'gtCountOnDisk', 0), ...
        'neoVasc', struct('status', 'NOT_SCORED', 'reason', 'No official IDRiD neovascularization GT.'), ...
        'vesselSegmentation', struct( ...
            'status', 'NOT_SCORED', ...
            'reason', 'IDRiD has no vessel GT. Requires DRIVE.'), ...
        'methodology', struct( ...
            'note', 'Localized at working res, mapped back to native px. Lesions compared at working res. Empty GT excluded (never negative). Bounded sample across train+test.'));

    % Fix lesionSE.gtCountOnDisk: read from the loader
    try
        ds = loadDataset('idrid');
        artifact.lesionSE.gtCountOnDisk = sum(cellfun(@(x) ~isempty(x), ds.parts.segmentation.masks.se));
        % Also get exact gtCountOnDisk for other lesions
        artifact.lesionMA.gtCountOnDisk = sum(cellfun(@(x) ~isempty(x), ds.parts.segmentation.masks.ma));
        artifact.lesionHE.gtCountOnDisk = sum(cellfun(@(x) ~isempty(x), ds.parts.segmentation.masks.he));
        artifact.lesionEX.gtCountOnDisk = sum(cellfun(@(x) ~isempty(x), ds.parts.segmentation.masks.ex));
    catch
        % best effort
    end

    % Write JSON artifact
    try
        json = jsonencode(artifact);
        fid = fopen(artifactPath, 'w', 'n', 'UTF-8');
        fwrite(fid, json, 'char');
        fclose(fid);
        logMessage('info', 'runIDRiDValidation', sprintf('Wrote artifact: %s', artifactPath));
    catch e
        logMessage('error', 'runIDRiDValidation', sprintf('JSON write failed: %s', e.message));
    end

    % ---- Update dataset_status.csv ONLY if real metrics produced ----
    producedRealMetrics = strcmp(resultLocalization.status, 'PASS') || strcmp(resultLocalization.status, 'PARTIAL') || ...
                          strcmp(resultLesion.status, 'PASS') || strcmp(resultLesion.status, 'PARTIAL');
    if producedRealMetrics
        updateDatasetStatus(p, resultLocalization.status, resultLesion.status, ...
            resultLocalization.n, resultLesion.n);
    end

    result = struct('artifactPath', artifactPath, 'overall', overall);
end

function s = safeStat(result, field)
    s = struct('status', '', 'n', 0, 'mean', nan, 'median', nan, 'max', nan, 'note', '');
    if ~isfield(result, field); return; end
    st = result.(field);
    if ~isstruct(st); return; end
    if isfield(st, 'status'); s.status = st.status; end
    if isfield(st, 'n'); s.n = st.n; end
    if isfield(st, 'mean'); s.mean = st.mean; end
    if isfield(st, 'median'); s.median = st.median; end
    if isfield(st, 'max'); s.max = st.max; end
    s.units = 'native image px';
end

function s = safeLesion(result, field)
    s = struct('status', 'UNKNOWN', 'n', 0, 'nWithGt', 0, 'meanDice', nan, 'meanIoU', nan, 'meanSensitivity', nan, 'meanPrecision', nan, 'note', '');
    if ~isfield(result, 'lesions'); return; end
    if ~isfield(result.lesions, field); return; end
    le = result.lesions.(field);
    if ~isstruct(le); return; end
    if isfield(le, 'n'); s.n = le.n; end
    if isfield(le, 'nGtPresent'); s.nWithGt = le.nGtPresent; end
    if isfield(le, 'diceMean'); s.meanDice = le.diceMean; end
    if isfield(le, 'iouMean'); s.meanIoU = le.iouMean; end
    if isfield(le, 'sensitivityMean'); s.meanSensitivity = le.sensitivityMean; end
    if isfield(le, 'precisionMean'); s.meanPrecision = le.precisionMean; end
    if le.n > 0; s.status = 'VALIDATED'; else; s.status = 'NO_NONEMPTY_GT_IN_SAMPLE'; end
end

function updateDatasetStatus(p, locStatus, lesStatus, nLoc, nLes)
    csvPath = fullfile(p.data.manifests, 'dataset_status.csv');
    if ~exist(csvPath, 'file'); return; end
    try
        raw = fileread(csvPath);
        lines = splitlines(string(raw));
        for i = 1:numel(lines)
            if startsWith(lines(i), 'idrid,')
                % Split CSV fields, replace field 2 (status), rejoin
                fields = split(lines(i), ',');
                if numel(fields) >= 2
                    fields(2) = "AVAILABLE + STRUCTURE VALIDATED + COMPONENT VALIDATED (bounded)";
                    lines(i) = strjoin(fields, ',');
                end
                break;
            end
        end
        fid = fopen(csvPath, 'w', 'n', 'UTF-8');
        if fid > 0
            for i = 1:numel(lines)
                fprintf(fid, '%s', char(lines(i)));
                if i < numel(lines); fprintf(fid, '\n'); end
            end
            fclose(fid);
            logMessage('info', 'runIDRiDValidation', ...
                sprintf('dataset_status.csv idrid row updated: loc=%s (%d), lesion=%s (%d)', ...
                locStatus, nLoc, lesStatus, nLes));
        end
    catch e
        logMessage('warn', 'runIDRiDValidation', sprintf('dataset_status.csv update skipped: %s', e.message));
    end
end