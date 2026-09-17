function demo_mock_pipeline()
%DEMO_MOCK_PIPELINE  Run the full mock pipeline end-to-end.
%
%   demo_mock_pipeline()
%
%   Executes the complete workflow Image -> Gate -> (Enhance) -> Analysis +
%   Grading -> Explainability + Confidence -> Review -> Report for the three
%   gate outcomes using synthetic images through the deterministic mock path.
%
%   Real outputs only: whatever the mock modules deterministically produce.
%   No clinical claims are implied.

    clc;
    fprintf('%s\n', repmat('=', 1, 72));
    fprintf('RetinaSense - mock end-to-end pipeline (honest placeholder modules)\n');
    fprintf('%s\n', repmat('=', 1, 72));

    scenarios = {'good', 'borderline', 'ungradable'};
    for i = 1:numel(scenarios)
        sc = scenarios{i};
        fprintf('\n>>> Scenario: %s\n', upper(sc));

        try
            c = runPipeline('scenario', sc, 'mock', true);
            summarizeCase(c, sc);
        catch ME
            fprintf('  Pipeline FAILED for %s: %s\n', sc, ME.message);
        end
    end

    % A second pass: human override exercise on a good case.
    fprintf('\n>>> Human review override exercise\n');
    c = runPipeline('scenario', 'good', 'mock', true);
    c = runPipeline('reviewer', struct('action','override','graderId','OPH-01', ...
        'overrideGrade', 3, 'notes', 'CADx found microaneurysms not flagged.'), ...
        'mock', true);
    fprintf('  override recorded: grade=%d -> finalReferral=%d (status=%s)\n', ...
        c.review.overrideGrade, c.review.finalReferral, c.review.status);

    fprintf('\n%s\n', repmat('=', 1, 72));
    fprintf('Demonstration complete. Reports under output/.\n');
end

function summarizeCase(c, label)
    fprintf('  patientId   : %s (%s eye)\n', c.meta.patientId, c.meta.eye);
    fprintf('  quality     : %s  (score %.2f)\n', c.quality.class, c.quality.score);
    if strcmp(c.quality.class, 'ungradable')
        fprintf('  recapture   : %s - %s\n', ...
            c.quality.recapture.reasonCode, c.quality.recapture.instruction);
        fprintf('  exitStage   : %s\n', c.pipeline.exitStage);
        return;
    end
    fprintf('  evidence    : confidence %s, lesions exudates=%d hmg=%d ma=%d nev=%d\n', ...
        c.evidence.confidence, ...
        c.evidence.lesions.exudates.count, c.evidence.lesions.hemorrhages.count, ...
        c.evidence.lesions.microaneurysms.count, c.evidence.lesions.neoVasc.count);
    if isfield(c.evidence, 'opticDiscDetail') && isstruct(c.evidence.opticDiscDetail)
        fprintf('  opticDisc   : %s (conf=%.2f)', ...
            c.evidence.opticDiscDetail.status, c.evidence.opticDiscDetail.confidence);
        if ~isempty(c.evidence.opticDiscDetail.center)
            fprintf(' at [%.0f, %.0f]', c.evidence.opticDiscDetail.center(1), c.evidence.opticDiscDetail.center(2));
        end
        fprintf('\n');
    end
    fprintf('  grade       : %d  (referable=%d, referableProb=%.3f)\n', ...
        c.grading.grade, c.grading.referable, c.grading.referableProb);
    fprintf('  calibrated  : conf=%.3f unc=%.3f reviewRequired=%d\n', ...
        c.calibrated.confidence, c.calibrated.uncertainty, c.calibrated.reviewRequired);
    fprintf('  review      : %s (status=%s), finalReferral=%d\n', ...
        c.review.action, c.review.status, c.review.finalReferral);
    fprintf('  report      : %s\n', c.report.filepath);
    fprintf('  stages      : %s\n', strjoin(c.pipeline.stages, ' -> '));
end