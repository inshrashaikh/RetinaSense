function raiseError(stage, code, msg, varargin)
%RAISEERROR  Structured, machine-readable error for the RetinaSense pipeline.
%
%   raiseError(stage, code, msg)
%   raiseError(stage, code, fmt, args...)
%
%   Throws an MException whose identifier encodes the failing module and a
%   stable error code, so callers / the orchestrator can branch on errors
%   deterministically instead of parsing strings.
%
%   identifier == sprintf('RetinaSense:%s:%s', stage, code)
%
%   Examples:
%     raiseError('ingestImage', 'DecodeFailed', 'Could not decode %s', f);
%     raiseError('classifyImage', 'MissingModel', 'No trained net for %s', b);

    if nargin > 3
        msg = sprintf(msg, varargin{:});
    end

    id = sprintf('RetinaSense:%s:%s', stage, code);
    ME = MException(id, '[%s] %s', stage, msg);

    % The orchestrator (runPipeline) catches these; logging happens there to
    % keep a single upstream error path. Not logging here avoids double logs.
    throw(ME);
end
