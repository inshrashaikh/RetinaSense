function evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions)
%BUILDEVidence  Stage 5e: assemble the advisory evidence struct.
%
%   evidence = buildEvidence(vesselMask, opticDisc, fovea, lesions)
%
%   CONTRACT (docs/ARCHITECTURE.md §4.3):
%     evidence.vesselMask  logical
%     evidence.opticDisc   [x,y] | []
%     evidence.fovea       [x,y] | []
%     evidence.lesions     per-class structs
%     evidence.confidence  'low' | 'medium' | 'high'
%
%   confidence encodes advisory certainty of the detections. Sprint 0 stubs
%   return empty detections => confidence 'low' (honest), and analysis NEVER
%   blocks grading.

    % Advisory confidence: with empty/detector-free Sprint-0 output it is 'low'
    % (honest). TODO(Sprint 7): derive from per-detector agreement when real
    % detectors land. Analysis never blocks grading regardless.
    confidence = 'low';

    evidence = struct( ...
        'vesselMask', vesselMask, ...
        'opticDisc',  opticDisc, ...
        'fovea',      fovea, ...
        'lesions',    lesions, ...
        'confidence', confidence);
end