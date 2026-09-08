function tests = test_analysis_modules
%TEST_ANALYSIS_MODULES  Contract tests for analysis/ modules (optic disc, fovea, vessels, lesions).
    tests = functiontests(localfunctions);
end

function test_locateOpticDiscContract(testCase)
    % Test that locateOpticDisc returns the expected struct fields
    img = syntheticFundusImage(256);
    p = analysis_config();
    result = locateOpticDisc(img, p.opticDisc);
    
    verifyTrue(testCase, isstruct(result));
    verifyTrue(testCase, isfield(result, 'center'));
    verifyTrue(testCase, isfield(result, 'bbox'));
    verifyTrue(testCase, isfield(result, 'confidence'));
    verifyTrue(testCase, isfield(result, 'status'));
    verifyTrue(testCase, isfield(result, 'method'));
    verifyTrue(testCase, isfield(result, 'note'));
    
    % Status must be one of expected values
    verifyTrue(testCase, ismember(result.status, {'detected', 'low_confidence', 'not_detected'}));
    
    % Confidence must be in [0,1]
    verifyTrue(testCase, result.confidence >= 0 && result.confidence <= 1);
    
    % If detected, center and bbox must be valid
    if strcmp(result.status, 'detected')
        verifyTrue(testCase, ~isempty(result.center) && numel(result.center) >= 2);
        verifyTrue(testCase, ~isempty(result.bbox) && numel(result.bbox) >= 4);
        verifyTrue(testCase, result.center(1) > 0 && result.center(1) <= size(img,2));
        verifyTrue(testCase, result.center(2) > 0 && result.center(2) <= size(img,1));
    end
end

function test_locateOpticDiscHandlesInvalidInput(testCase)
    p = analysis_config();
    
    % Empty image
    result = locateOpticDisc([], p.opticDisc);
    verifyEqual(testCase, result.status, 'not_detected');
    verifyTrue(testCase, isempty(result.center));
    
    % Non-RGB image
    img = uint8(ones(100, 100));
    result = locateOpticDisc(img, p.opticDisc);
    verifyEqual(testCase, result.status, 'not_detected');
    
    % Wrong number of channels
    img = uint8(ones(100, 100, 4));
    result = locateOpticDisc(img, p.opticDisc);
    verifyEqual(testCase, result.status, 'not_detected');
end

function test_locateOpticDiscDeterministic(testCase)
    % Same input should produce same output
    img = syntheticFundusImage(256);
    p = analysis_config();
    
    r1 = locateOpticDisc(img, p.opticDisc);
    r2 = locateOpticDisc(img, p.opticDisc);
    
    verifyEqual(testCase, r1.status, r2.status);
    if ~isempty(r1.center) && ~isempty(r2.center)
        verifyEqual(testCase, r1.center, r2.center);
        verifyEqual(testCase, r1.confidence, r2.confidence);
    end
end

function test_locateOpticDiscWithConfigVariation(testCase)
    img = syntheticFundusImage(256);
    p = analysis_config();
    
    % Test with different temporal bias
    p2 = p;
    p2.opticDisc.temporalSideBias = 0.4; % left side
    r1 = locateOpticDisc(img, p.opticDisc);
    r2 = locateOpticDisc(img, p2.opticDisc);
    
    % Both should produce valid results (though possibly different)
    verifyTrue(testCase, ismember(r1.status, {'detected', 'low_confidence', 'not_detected'}));
    verifyTrue(testCase, ismember(r2.status, {'detected', 'low_confidence', 'not_detected'}));
end

function test_locateFoveaContract(testCase)
    img = syntheticFundusImage(256);
    p = analysis_config();
    
    % Test without optic disc
    fovea = locateFovea(img, struct('center',[], 'status','not_detected'), p.fovea);
    verifyTrue(testCase, isempty(fovea) || (numel(fovea) >= 2));
    
    % Test with optic disc
    disc = struct('center', [150, 120], 'bbox', [130, 100, 40, 40], 'status', 'detected');
    fovea = locateFovea(img, disc, p.fovea);
    verifyTrue(testCase, numel(fovea) >= 2);
    verifyTrue(testCase, fovea(1) > disc.center(1)); % temporal (right) of disc for right eye
end

function test_buildEvidenceContract(testCase)
    img = syntheticFundusImage(256);
    p = analysis_config();
    
    vesselMask = false(size(img,1), size(img,2));
    disc = locateOpticDisc(img, p.opticDisc);
    fovea = locateFovea(img, disc, p.fovea);
    
    % Create minimal lesions struct
    lesions = struct( ...
        'exudates', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)), ...
        'hemorrhages', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)), ...
        'microaneurysms', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)), ...
        'neoVasc', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)));
    
    evidence = buildEvidence(vesselMask, disc, fovea, lesions);
    
    verifyTrue(testCase, isstruct(evidence));
    verifyTrue(testCase, isfield(evidence, 'vesselMask'));
    verifyTrue(testCase, isfield(evidence, 'opticDisc'));
    verifyTrue(testCase, isfield(evidence, 'fovea'));
    verifyTrue(testCase, isfield(evidence, 'lesions'));
    verifyTrue(testCase, isfield(evidence, 'confidence'));
    verifyTrue(testCase, isfield(evidence, 'opticDiscDetail'));
    
    % Contract: opticDisc must be [x,y] | []
    verifyTrue(testCase, isempty(evidence.opticDisc) || numel(evidence.opticDisc) >= 2);
    verifyTrue(testCase, isempty(evidence.fovea) || numel(evidence.fovea) >= 2);
    
    % Confidence must be valid
    verifyTrue(testCase, ismember(evidence.confidence, {'low', 'medium', 'high'}));
    
    % opticDiscDetail must be struct with expected fields
    verifyTrue(testCase, isstruct(evidence.opticDiscDetail));
end

function test_buildEvidenceConfidenceLevels(testCase)
    img = syntheticFundusImage(256);
    p = analysis_config();
    
    % All empty -> low confidence
    vesselMask = false(size(img,1), size(img,2));
    disc = struct('center', [], 'status', 'not_detected');
    fovea = [];
    lesions = struct( ...
        'exudates', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)), ...
        'hemorrhages', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)), ...
        'microaneurysms', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)), ...
        'neoVasc', struct('map', false(size(img,1),size(img,2)), 'count', 0, 'features', zeros(4,0)));
    
    evidence = buildEvidence(vesselMask, disc, fovea, lesions);
    verifyEqual(testCase, evidence.confidence, 'low');
    
    % With disc detected -> at least medium
    disc = struct('center', [150, 120], 'status', 'detected');
    evidence = buildEvidence(vesselMask, disc, fovea, lesions);
    verifyTrue(testCase, ismember(evidence.confidence, {'medium', 'high'}));
end

function test_overlayOpticDiscBasic(testCase)
    img = syntheticFundusImage(256);
    disc = struct('center', [150, 120], 'bbox', [130, 100, 40, 40], ...
        'confidence', 0.85, 'status', 'detected', 'method', 'test');
    
    overlay = overlayOpticDisc(img, disc);
    
    verifyEqual(testCase, size(overlay), size(img));
    verifyEqual(testCase, class(overlay), 'uint8');
    % Overlay should be different from original (has drawing)
    verifyTrue(testCase, ~isequal(overlay, img));
end

function test_overlayOpticDiscNotDetected(testCase)
    img = syntheticFundusImage(256);
    disc = struct('center', [], 'status', 'not_detected', 'confidence', 0.1);
    
    overlay = overlayOpticDisc(img, disc);
    
    verifyEqual(testCase, size(overlay), size(img));
    % Should have text overlay indicating not_detected
    verifyTrue(testCase, ~isequal(overlay, img));
end

function test_analyzeRetinaIntegration(testCase)
    img = syntheticFundusImage(256);
    p = analysis_config();
    
    evidence = analyzeRetina(img, [], p);
    
    verifyTrue(testCase, isstruct(evidence));
    verifyTrue(testCase, isfield(evidence, 'opticDisc'));
    verifyTrue(testCase, isfield(evidence, 'opticDiscDetail'));
    verifyTrue(testCase, isfield(evidence, 'confidence'));
    verifyTrue(testCase, ismember(evidence.confidence, {'low', 'medium', 'high'}));
end

function img = syntheticFundusImage(size)
%SYNTHETICFUNDUSIMAGE  Generate a deterministic synthetic fundus image for testing.
    rng(42, 'twister');
    if isscalar(size)
        h = size; w = size;
    else
        h = size(1); w = size(2);
    end
    
    % Background
    bg = 70 + 40 * rand(h, w);
    
    % Optic disc-like bright region (temporal side, ~60% from left)
    discX = round(w * 0.6);
    discY = round(h * 0.5);
    discR = round(min(h, w) * 0.1);
    [yy, xx] = ndgrid(1:h, 1:w);
    discMask = sqrt((xx - discX).^2 + (yy - discY).^2) <= discR;
    
    % Vessel-like structures
    vesselMask = false(h, w);
    for i = 1:5
        x1 = randi(w); y1 = randi(h);
        x2 = randi(w); y2 = randi(h);
        vesselMask = vesselMask | createLineMask(y1, x1, y2, x2, 2, h, w);
    end
    
    % Build RGB: green channel has best contrast
    r = uint8(bg + 120 * discMask);
    g = uint8(bg + 60 * discMask + 30 * vesselMask);
    b = uint8(bg + 20 * discMask);
    
    img = cat(3, r, g, b);
end

function mask = createLineMask(y1, x1, y2, x2, thickness, h, w)
    % Simple line drawing for synthetic vessels
    mask = false(h, w);
    n = max(abs(x2-x1), abs(y2-y1)) + 1;
    xs = round(linspace(x1, x2, n));
    ys = round(linspace(y1, y2, n));
    for i = 1:n
        x = xs(i); y = ys(i);
        if x > 0 && x <= w && y > 0 && y <= h
            xr = max(1, x-thickness):min(w, x+thickness);
            yr = max(1, y-thickness):min(h, y+thickness);
            mask(yr, xr) = true;
        end
    end
end