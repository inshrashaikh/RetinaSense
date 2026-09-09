function tests = test_pipeline_e2e
%TEST_PIPELINE_E2E  End-to-end integration: all gate outcomes -> report.
    tests = functiontests(localfunctions);
end

function test_allScenariosEndToEnd(testCase)
    p = paths();
    for sc = {'good', 'borderline', 'ungradable'}
        c = runPipeline('scenario', sc{1});
        verifyTrue(testCase, ismember(c.quality.class, {'good','borderline','ungradable'}));
        if ~strcmp(c.quality.class, 'ungradable')
            verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'report')));
            verifyTrue(testCase, ~isempty(c.report.filepath));
            verifyTrue(testCase, exist(c.report.filepath, 'file') == 2);
            verifyTrue(testCase, ~isempty(c.report.summary));
            verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'grading')));
        end
    end
end

function test_fromFileToReport(testCase)
    meta = struct('patientId','IP-42','eye','left', ...
        'timestamp','2026-01-01T00:00:00','phcId','PHC-ALPHA');
    c = runPipeline(meta, fullfile(paths().assets, 'synthetic_fundus_demo.png'));
    verifyTrue(testCase, ~isempty(c.image));
    verifyEqual(testCase, c.meta.patientId, 'IP-42');
    if ~strcmp(c.quality.class, 'ungradable')
        verifyTrue(testCase, any(strcmp(c.pipeline.stages, 'report')));
    end
end

function test_logsWritten(testCase)
    p = paths();
    if exist(p.log.file, 'file') == 2
        delete(p.log.file);
    end
    runPipeline('scenario', 'good');
    verifyTrue(testCase, exist(p.log.file, 'file') == 2);
end