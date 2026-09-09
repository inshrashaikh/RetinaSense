function launchRetinaSenseApp(varargin)
%LAUNCHRETINASENSEAPP  Launch the ophthalmologist review interface.
%
%   launchRetinaSenseApp()                    % launch with empty state
%   launchRetinaSenseApp('good')              % launch with mock good case
%   launchRetinaSenseApp('borderline')        % launch with mock borderline
%   launchRetinaSenseApp(caseData)            % launch with a populated Case
%
%   Opens the RetinaSenseApp review UI. The application runs until the user
%   closes the window.
%
%   Requires MATLAB R2016b+ with App Designer or uifigure support.

    fprintf('RetinaSense — Ophthalmologist Review Interface\n');
    fprintf('Decision-support system. Not a diagnosis.\n\n');

    try
        if nargin == 0
            app = RetinaSenseApp();
        else
            app = RetinaSenseApp(varargin{:});
        end

        fprintf('Application launched. Close the window to exit.\n');
    catch ME
        if contains(ME.message, 'uifigure') || contains(ME.message, 'No suitable')
            fprintf('\n');
            fprintf('ERROR: uifigure not available in this MATLAB installation.\n');
            fprintf('Required: MATLAB R2016b+ with App Designer support.\n');
            fprintf('\n');
            fprintf('To test the review workflow without UI:\n');
            fprintf('  c = runPipeline(''scenario'', ''good'');\n');
            fprintf('  cfg = experiment_config();\n');
            fprintf('  review = submitReview(c, struct(''action'',''approve'',...\n');
            fprintf('      ''graderId'',''OPH-01'',''overrideGrade'',NaN,''notes'',''''), cfg);\n');
            fprintf('  report = buildReport(c, cfg);\n');
        else
            fprintf('Launch failed: %s\n', ME.message);
        end
    end
end
