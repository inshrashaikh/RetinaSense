function logMessage(level, stage, msg)
%LOGMESSAGE  Structured logging for the RetinaSense pipeline.
%
%   logMessage(level, stage, msg)
%
%   level: 'info' | 'warn' | 'error' | 'debug'
%   stage: name of the pipeline stage or module (e.g. 'assessQuality', 'PIPELINE')
%   msg:   human-readable message (no secrets, no PII)
%
%   Emits one consistent line: [timestamp] [LEVEL] [stage] message to stdout,
%   and to the log file configured in config/paths.m (cfg.log.file) if set.
%
%   This is the only sanctioned logging entry point, so the CLI and UI share
%   a single format. Replace the internals (e.g. file sink) freely; keep the
%   signature stable so teammates can rely on it.

    ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    line = sprintf('%s [%s] [%s] %s', ts, upper(level), stage, msg);
    fprintf('%s\n', line);

    try
        cfg = paths();
        if ~isempty(cfg.log.file)
            fid = fopen(cfg.log.file, 'a');
            if fid > 0
                fprintf(fid, '%s\n', line);
                fclose(fid);
            end
        end
    catch
        % Logging must never break the pipeline.
    end
end
