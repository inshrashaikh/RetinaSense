function filepath = renderReport(report, params)
%RENDERREPORT  Stage 9c: render the report to a file.
%
%   filepath = renderReport(report, params)
%
%   TODO(Sprint 5): professional PDF/PNG rendering (report + evidence overlay
%   + attention image + disclaimer). For now emits a minimal plain-text report
%   to output/ so the filepath contract is fulfilled and testable.

    if nargin < 2 || isempty(params); p = paths(); params = struct('out', p.output); end
    if ~isfield(params, 'out'); params.out = paths().output; end
    if ~exist(params.out, 'dir'); mkdir(params.out); end

    filepath = fullfile(params.out, sprintf('report_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));

    fid = fopen(filepath, 'w');
    if fid <= 0
        raiseError('renderReport', 'WriteFailed', 'Cannot write report to %s', filepath);
    end
    fprintf(fid, '%s\n', '--- RetinaSense Screening Report ---');
    fprintf(fid, '%s\n', report.summary);
    if isfield(report, 'disclaimer'); fprintf(fid, '\n%s\n', report.disclaimer); end
    fclose(fid);
end