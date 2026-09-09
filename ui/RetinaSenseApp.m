classdef RetinaSenseApp < handle
    %RETINASENSEAPP Programmatic prototype of the Sprint 5 review UI.
    %
    % This class mirrors the intended App Designer workflow:
    %   fundus image + model attention + evidence
    %   quality / grading / calibration information
    %   approve / override / recapture
    %   reviewer ID + notes
    %
    % The review action is delegated to reporting/submitReview.m.

    properties
        UIFigure
        MainGrid

        % Image panels
        FundusAxes
        GradCAMAxes
        EvidenceAxes

        % Information panel
        QualityValue
        GradeValue
        ReferableValue
        ConfidenceValue
        UncertaintyValue
        ReviewRequiredValue
        FinalReferralValue

        % Review controls
        ReviewerIDField
        ActionDropDown
        OverrideGradeField
        NotesArea
        SubmitButton
        StatusLabel

        CaseData
    end

    methods

        function app = RetinaSenseApp(caseData)
            if nargin < 1 || isempty(caseData)
                caseData = newCase();
            end

            app.CaseData = caseData;
            app.createComponents();
            app.refreshView();
        end


        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

    end


    methods (Access = private)

        function createComponents(app)

            app.UIFigure = uifigure( ...
                'Name', 'RetinaSense — Ophthalmologist Review', ...
                'Position', [100 100 1500 900]);

            app.MainGrid = uigridlayout(app.UIFigure, [4 3]);

            app.MainGrid.RowHeight = ...
                {30, '1x', '1x', 250};

            app.MainGrid.ColumnWidth = ...
                {'1x', '1x', '1x'};

            % -------------------------------------------------------------
            % Header
            % -------------------------------------------------------------
            header = uilabel(app.MainGrid);
            header.Text = 'RetinaSense Screening Review';
            header.FontSize = 18;
            header.FontWeight = 'bold';
            header.HorizontalAlignment = 'center';

            header.Layout.Row = 1;
            header.Layout.Column = [1 3];

            % -------------------------------------------------------------
            % Fundus image
            % -------------------------------------------------------------
            fundusPanel = uipanel(app.MainGrid);
            fundusPanel.Title = 'Fundus Image';
            fundusPanel.Layout.Row = 2;
            fundusPanel.Layout.Column = 1;

            fundusGrid = uigridlayout(fundusPanel, [1 1]);

            app.FundusAxes = uiaxes(fundusGrid);
            app.FundusAxes.XTick = [];
            app.FundusAxes.YTick = [];
            app.FundusAxes.Box = 'on';

            % -------------------------------------------------------------
            % Grad-CAM
            % -------------------------------------------------------------
            attentionPanel = uipanel(app.MainGrid);
            attentionPanel.Title = 'Model Attention (Grad-CAM)';
            attentionPanel.Layout.Row = 2;
            attentionPanel.Layout.Column = 2;

            attentionGrid = uigridlayout(attentionPanel, [1 1]);

            app.GradCAMAxes = uiaxes(attentionGrid);
            app.GradCAMAxes.XTick = [];
            app.GradCAMAxes.YTick = [];
            app.GradCAMAxes.Box = 'on';

            % -------------------------------------------------------------
            % Evidence
            % -------------------------------------------------------------
            evidencePanel = uipanel(app.MainGrid);
            evidencePanel.Title = 'Evidence / Lesion Overlay';
            evidencePanel.Layout.Row = 2;
            evidencePanel.Layout.Column = 3;

            evidenceGrid = uigridlayout(evidencePanel, [1 1]);

            app.EvidenceAxes = uiaxes(evidenceGrid);
            app.EvidenceAxes.XTick = [];
            app.EvidenceAxes.YTick = [];
            app.EvidenceAxes.Box = 'on';

            % -------------------------------------------------------------
            % Assessment panel
            % -------------------------------------------------------------
            infoPanel = uipanel(app.MainGrid);
            infoPanel.Title = 'Assessment';
            infoPanel.Layout.Row = 3;
            infoPanel.Layout.Column = [1 3];

            infoGrid = uigridlayout(infoPanel, [2 7]);
            infoGrid.RowHeight = {'1x', '1x'};
            infoGrid.ColumnWidth = ...
                {'1x','1x','1x','1x','1x','1x','1x'};

            app.QualityValue = addMetric( ...
                infoGrid, 1, 1, 'Quality');

            app.GradeValue = addMetric( ...
                infoGrid, 1, 2, 'AI DR Grade');

            app.ReferableValue = addMetric( ...
                infoGrid, 1, 3, 'AI Referable');

            app.ConfidenceValue = addMetric( ...
                infoGrid, 1, 4, 'Confidence');

            app.UncertaintyValue = addMetric( ...
                infoGrid, 1, 5, 'Uncertainty');

            app.ReviewRequiredValue = addMetric( ...
                infoGrid, 1, 6, 'Review Required');

            app.FinalReferralValue = addMetric( ...
                infoGrid, 1, 7, 'Final Referral');

            % Second row: summary/status
            summaryLabel = uilabel(infoGrid);
            summaryLabel.Text = 'Review status appears after submission.';
            summaryLabel.Layout.Row = 2;
            summaryLabel.Layout.Column = [1 4];

            app.StatusLabel = uilabel(infoGrid);
            app.StatusLabel.Text = 'Ready for review';
            app.StatusLabel.FontWeight = 'bold';
            app.StatusLabel.Layout.Row = 2;
            app.StatusLabel.Layout.Column = [5 7];

            % -------------------------------------------------------------
            % Review controls
            % -------------------------------------------------------------
            reviewPanel = uipanel(app.MainGrid);
            reviewPanel.Title = 'Human Review';
            reviewPanel.Layout.Row = 4;
            reviewPanel.Layout.Column = [1 3];

            reviewGrid = uigridlayout(reviewPanel, [4 4]);

            reviewGrid.RowHeight = {30, 30, '1x', 40};
            reviewGrid.ColumnWidth = {150, 180, 150, '1x'};

            reviewerLabel = uilabel(reviewGrid);
            reviewerLabel.Text = 'Reviewer ID';
            reviewerLabel.Layout.Row = 1;
            reviewerLabel.Layout.Column = 1;

            app.ReviewerIDField = uieditfield(reviewGrid, 'text');
            app.ReviewerIDField.Placeholder = 'Enter reviewer ID';
            app.ReviewerIDField.Layout.Row = 1;
            app.ReviewerIDField.Layout.Column = 2;

            actionLabel = uilabel(reviewGrid);
            actionLabel.Text = 'Action';
            actionLabel.Layout.Row = 1;
            actionLabel.Layout.Column = 3;

            app.ActionDropDown = uidropdown(reviewGrid);
            app.ActionDropDown.Items = ...
                {'approve', 'override', 'recapture'};
            app.ActionDropDown.Value = 'approve';
            app.ActionDropDown.Layout.Row = 1;
            app.ActionDropDown.Layout.Column = 4;

            overrideLabel = uilabel(reviewGrid);
            overrideLabel.Text = 'Override Grade (0–4)';
            overrideLabel.Layout.Row = 2;
            overrideLabel.Layout.Column = 1;

            app.OverrideGradeField = uieditfield( ...
                reviewGrid, 'numeric');

            app.OverrideGradeField.Limits = [0 4];
            app.OverrideGradeField.RoundFractionalValues = 'on';
            app.OverrideGradeField.Value = 0;
            app.OverrideGradeField.Layout.Row = 2;
            app.OverrideGradeField.Layout.Column = 2;

            notesLabel = uilabel(reviewGrid);
            notesLabel.Text = 'Notes';
            notesLabel.VerticalAlignment = 'top';
            notesLabel.Layout.Row = 3;
            notesLabel.Layout.Column = 1;

            app.NotesArea = uitextarea(reviewGrid);
            app.NotesArea.Placeholder = ...
                'Add reviewer notes or rationale...';
            app.NotesArea.Layout.Row = 3;
            app.NotesArea.Layout.Column = [2 4];

            app.SubmitButton = uibutton( ...
                reviewGrid, 'push');

            app.SubmitButton.Text = 'Submit Review';
            app.SubmitButton.FontWeight = 'bold';
            app.SubmitButton.ButtonPushedFcn = ...
                @(~,~) app.submitReview();

            app.SubmitButton.Layout.Row = 4;
            app.SubmitButton.Layout.Column = [3 4];

        end


        function refreshView(app)

            c = app.CaseData;

            % -------------------------------------------------------------
            % Fundus
            % -------------------------------------------------------------
            cla(app.FundusAxes);

            if hasUsableImage(c.image)
                imagesc(app.FundusAxes, c.image);
                axis(app.FundusAxes, 'image');
                app.FundusAxes.Visible = 'off';
            else
                showPlaceholder( ...
                    app.FundusAxes, ...
                    'Fundus image unavailable');
            end

            % -------------------------------------------------------------
            % Grad-CAM
            % -------------------------------------------------------------
            cla(app.GradCAMAxes);

            if hasUsableImage(c.explain.gradCam)
                imagesc(app.GradCAMAxes, c.explain.gradCam);
                axis(app.GradCAMAxes, 'image');
                app.GradCAMAxes.Visible = 'off';
            else
                showPlaceholder( ...
                    app.GradCAMAxes, ...
                    'Grad-CAM unavailable');
            end

            % -------------------------------------------------------------
            % Evidence
            % -------------------------------------------------------------
            cla(app.EvidenceAxes);

            if hasUsableImage(c.explain.evidenceOverlay)
                imagesc(app.EvidenceAxes, c.explain.evidenceOverlay);
                axis(app.EvidenceAxes, 'image');
                app.EvidenceAxes.Visible = 'off';
            elseif hasEvidence(c)
                showPlaceholder( ...
                    app.EvidenceAxes, ...
                    'Evidence overlay unavailable');
            else
                showPlaceholder( ...
                    app.EvidenceAxes, ...
                    'No lesion evidence available');
            end

            % -------------------------------------------------------------
            % Assessment values
            % -------------------------------------------------------------
            app.QualityValue.Text = ...
                safeText(c.quality.class);

            app.GradeValue.Text = ...
                safeNumber(c.grading.grade);

            app.ReferableValue.Text = ...
                safeLogical(c.grading.referable);

            app.ConfidenceValue.Text = ...
                safeNumber(c.calibrated.confidence);

            app.UncertaintyValue.Text = ...
                safeNumber(c.calibrated.uncertainty);

            app.ReviewRequiredValue.Text = ...
                safeLogical(c.calibrated.reviewRequired);

            app.FinalReferralValue.Text = ...
                safeLogical(c.review.finalReferral);

            if c.calibrated.reviewRequired
                app.StatusLabel.Text = ...
                    'Human review required';
            else
                app.StatusLabel.Text = ...
                    'Review ready';
            end

        end


        function submitReview(app)

            action = app.ActionDropDown.Value;
            graderId = strtrim(app.ReviewerIDField.Value);

            if isempty(graderId)
                app.StatusLabel.Text = ...
                    'Reviewer ID is required.';
                return;
            end

            notes = strjoin( ...
                cellstr(app.NotesArea.Value), ...
                newline);

            overrideGrade = NaN;

            if strcmp(action, 'override')
                overrideGrade = ...
                    app.OverrideGradeField.Value;
            end

            reviewerInput = struct( ...
                'action', action, ...
                'graderId', graderId, ...
                'overrideGrade', overrideGrade, ...
                'notes', notes);

            try
                review = submitReview( ...
                    app.CaseData, ...
                    reviewerInput);

                app.CaseData.review = review;

                app.FinalReferralValue.Text = ...
                    safeLogical(review.finalReferral);

                app.StatusLabel.Text = sprintf( ...
                    'Submitted: %s (%s)', ...
                    review.action, ...
                    review.status);

            catch ME
                app.StatusLabel.Text = ...
                    ['Review failed: ' ME.message];
            end

        end

    end
end


function valueLabel = addMetric(parent, row, col, titleText)

    metricGrid = uigridlayout(parent, [2 1]);
    metricGrid.RowHeight = {20, '1x'};
    metricGrid.Layout.Row = row;
    metricGrid.Layout.Column = col;

    titleLabel = uilabel(metricGrid);
    titleLabel.Text = titleText;
    titleLabel.HorizontalAlignment = 'center';
    titleLabel.FontWeight = 'bold';

    valueLabel = uilabel(metricGrid);
    valueLabel.Text = 'n/a';
    valueLabel.HorizontalAlignment = 'center';
    valueLabel.FontSize = 16;

end


function tf = hasUsableImage(value)

    tf = (isnumeric(value) || islogical(value)) && ...
         ~isempty(value) && ...
         ndims(value) >= 2 && ...
         ndims(value) <= 3;

end


function tf = hasEvidence(c)

    tf = false;

    if ~isstruct(c.evidence) || ...
            ~isfield(c.evidence, 'lesions')
        return;
    end

    lesionNames = ...
        {'exudates', 'hemorrhages', ...
         'microaneurysms', 'neoVasc'};

    for i = 1:numel(lesionNames)

        lesion = c.evidence.lesions.(lesionNames{i});

        if ~isstruct(lesion)
            continue;
        end

        if isfield(lesion, 'map') && ...
                hasUsableImage(lesion.map)
            tf = true;
            return;
        end

        if isfield(lesion, 'count') && ...
                isnumeric(lesion.count) && ...
                isscalar(lesion.count) && ...
                isfinite(lesion.count) && ...
                lesion.count > 0
            tf = true;
            return;
        end

    end

end


function showPlaceholder(ax, message)

    axis(ax, 'off');

    text(ax, 0.5, 0.5, message, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 12);

end


function txt = safeNumber(value)

    if isempty(value) || ...
            ~isnumeric(value) || ...
            ~isscalar(value) || ...
            ~isfinite(value)

        txt = 'n/a';
        return;
    end

    txt = sprintf('%.3f', value);

end


function txt = safeLogical(value)

    if isempty(value)
        txt = 'false';
        return;
    end

    txt = lower(char(string(logical(value))));

end


function txt = safeText(value)

    if isempty(value)
        txt = 'n/a';
    elseif isstring(value)
        txt = char(value(1));
    elseif ischar(value)
        txt = value;
    else
        txt = char(string(value));
    end

end