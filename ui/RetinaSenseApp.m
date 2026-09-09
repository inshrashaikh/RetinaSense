classdef RetinaSenseApp < handle
%RETINASENSEAPP  Ophthalmologist review UI for RetinaSense.
%
%   app = RetinaSenseApp()                % launch with no case
%   app = RetinaSenseApp(caseData)        % launch with a populated Case
%   app = RetinaSenseApp('mock', 'good')  % launch with mock pipeline case
%
%   Programmatic uifigure-based application implementing the ophthalmologist
%   review interface (docs/ARCHITECTURE.md §5, Sprint 5). Serves as both a
%   standalone review tool and the reference implementation for the .mlapp
%   version.
%
%   LAYOUT:
%     Top bar:     title + status
%     Left panel:  original retinal image
%     Right panel: screening result + calibration
%     Center:      evidence/visualization tab group
%     Bottom:      human review controls + notes
%
%   CONTRACTS CONSUMED:
%     submitReview(case, reviewerInput, params)  — reporting/submitReview.m
%     buildReport(case, params)                  — reporting/buildReport.m
%     renderReport(report, params)               — reporting/renderReport.m
%
%   MEDICAL SAFETY:
%     - Screening decision-support only, not a diagnosis.
%     - Grad-CAM is model attention, not causality.
%     - Lesion outputs are candidate evidence, not confirmed diagnosis.
%     - No clinical claim is made by this UI.

    % ---- Properties ----
    properties (Access = public)
        Fig             matlab.ui.Figure
        Case            struct          % current loaded Case
        Config          struct          % experiment_config() copy
        ReviewerId      char = ''       % reviewer identifier
    end

    properties (Access = private)
        % ---- Layout panels ----
        TopBar          matlab.ui.container.Panel
        LeftPanel       matlab.ui.container.Panel
        RightPanel      matlab.ui.container.Panel
        CenterPanel     matlab.ui.container.Panel
        BottomPanel     matlab.ui.container.Panel

        % ---- Image display ----
        ImageAxes       matlab.ui.control.UIAxes

        % ---- Screening result labels ----
        GradeLabel          matlab.ui.control.Label
        GradeDetailLabel    matlab.ui.control.Label
        ConfidenceLabel     matlab.ui.control.Label
        UncertaintyLabel    matlab.ui.control.Label
        ReviewReqLabel      matlab.ui.control.Label
        QualityLabel        matlab.ui.control.Label
        PatientLabel        matlab.ui.control.Label
        EvidenceConfLabel   matlab.ui.control.Label

        % ---- Evidence/visualization tabs ----
        VizTabGroup     matlab.ui.container.TabGroup
        OriginalTab     matlab.ui.container.Tab
        GradCAMTab      matlab.ui.container.Tab
        VesselsTab      matlab.ui.container.Tab
        StructuresTab   matlab.ui.container.Tab
        LesionsTab      matlab.ui.container.Tab

        OriginalAxes    matlab.ui.control.UIAxes
        GradCAMAxes     matlab.ui.control.UIAxes
        VesselsAxes     matlab.ui.control.UIAxes
        StructuresAxes  matlab.ui.control.UIAxes
        LesionsAxes     matlab.ui.control.UIAxes

        % ---- Lesion detail labels ----
        ExudatesLabel       matlab.ui.control.Label
        HemorrhagesLabel    matlab.ui.control.Label
        MicroaneurysmsLabel matlab.ui.control.Label
        NeoVascLabel        matlab.ui.control.Label

        % ---- Review controls ----
        ApproveButton       matlab.ui.control.Button
        OverrideButton      matlab.ui.control.Button
        RecaptureButton     matlab.ui.control.Button
        OverrideGradeDropdown matlab.ui.control.DropDown
        OverrideGradeLabel  matlab.ui.control.Label
        ReviewerNotesField  matlab.ui.control.TextArea
        ReviewerIdField     matlab.ui.control.EditField
        StatusLabel         matlab.ui.control.Label
        GenerateReportButton matlab.ui.control.Button
        OpenReportButton    matlab.ui.control.Button

        % ---- Status bar ----
        StatusFieldLabel    matlab.ui.control.Label

        % ---- Internal state ----
        CurrentReport       struct
        ReviewComplete      logical = false
    end

    % ---- Constants (medical safety) ----
    properties (Constant, Access = private)
        DISCLAIMER = 'Screening decision-support only. Not a diagnosis and not a replacement for an ophthalmologist.';
        ATTENTION_NOTE = 'Grad-CAM represents model attention, not proof of causality.';
        CANDIDATE_NOTE = 'Lesion outputs are candidate evidence, not confirmed diagnosis.';
        GRADE_LABELS = {'No DR', 'Mild NPDR', 'Moderate NPDR', 'Severe NPDR', 'Proliferative DR'};
    end

    % ---- Public methods ----
    methods (Access = public)

        function app = RetinaSenseApp(varargin)
        %RETINASENSEAPP  Constructor: build the review UI.
        %
        %   app = RetinaSenseApp()
        %   app = RetinaSenseApp(caseData)
        %   app = RetinaSenseApp('mock', scenario)

            app.Config = experiment_config();

            % Parse arguments
            caseData = [];
            mockScenario = '';
            i = 1;
            while i <= nargin
                if isstruct(varargin{i}) && isfield(varargin{i}, 'image')
                    caseData = varargin{i};
                elseif ischar(varargin{i}) || isstring(varargin{i})
                    arg = char(varargin{i});
                    if strcmpi(arg, 'mock') && i < nargin
                        mockScenario = char(varargin{i+1});
                        i = i + 1;
                    elseif strcmpi(arg, 'reviewer')
                        if i < nargin && isstruct(varargin{i+1})
                            app.ReviewerId = varargin{i+1}.graderId;
                            i = i + 1;
                        end
                    end
                end
                i = i + 1;
            end

            % Build the UI
            buildLayout(app);

            % Load case if provided
            if ~isempty(mockScenario)
                loadMockCase(app, mockScenario);
            elseif ~isempty(caseData)
                loadCase(app, caseData);
            end
        end

        function delete(app)
        %DELETE  Clean up figure on app destruction.
            if ishandle(app.Fig)
                delete(app.Fig);
            end
        end
    end

    % ---- Case loading ----
    methods (Access = public)

        function loadMockCase(app, scenario)
        %LOADMOCKCASE  Run pipeline and load a mock case.
            setStatus(app, 'Running pipeline...');
            try
                c = runPipeline('scenario', scenario);
                loadCase(app, c);
                setStatus(app, sprintf('Loaded mock case: %s', scenario));
            catch ME
                setStatus(app, sprintf('Error loading mock case: %s', ME.message));
            end
        end

        function loadCase(app, caseData)
        %LOADCASE  Populate all UI panels from a Case struct.
            app.Case = caseData;
            app.ReviewComplete = false;

            % Validate minimum fields
            required = {'meta', 'quality', 'grading', 'calibrated', 'evidence', 'explain'};
            for i = 1:numel(required)
                if ~isfield(caseData, required{i})
                    setStatus(app, sprintf('Invalid case: missing %s', required{i}));
                    return;
                end
            end

            % Update all panels
            updateImagePanel(app);
            updateScreeningResult(app);
            updateVisualizationTabs(app);
            updateLesionEvidence(app);
            updateReviewControls(app);

            setStatus(app, 'Case loaded. Ready for review.');
        end
    end

    % ---- Review workflow ----
    methods (Access = private)

        function onApprove(app, ~, ~)
        %ONAPPROVE  Handle approve button press.
            if isempty(app.Case) || ~isfield(app.Case, 'grading')
                setStatus(app, 'No case loaded.');
                return;
            end

            reviewerInput = struct( ...
                'action',        'approve', ...
                'graderId',      getReviewerId(app), ...
                'overrideGrade', NaN, ...
                'notes',         char(app.ReviewerNotesField.Value));

            try
                review = submitReview(app.Case, reviewerInput, app.Config);
                app.Case.review = review;
                app.ReviewComplete = true;
                updateReviewStatus(app, review);
                setStatus(app, 'Case approved.');
            catch ME
                setStatus(app, sprintf('Approve failed: %s', ME.message));
            end
        end

        function onOverride(app, ~, ~)
        %ONOVERRIDE  Handle override button press.
            if isempty(app.Case) || ~isfield(app.Case, 'grading')
                setStatus(app, 'No case loaded.');
                return;
            end

            % Get selected override grade
            gradeStr = app.OverrideGradeDropdown.Value;
            if isempty(gradeStr) || startsWith(gradeStr, 'Select')
                setStatus(app, 'Please select an override grade.');
                return;
            end
            overrideGrade = str2double(extractBefore(gradeStr, ' '));
            if isnan(overrideGrade) || overrideGrade < 0 || overrideGrade > 4
                setStatus(app, 'Invalid override grade.');
                return;
            end

            reviewerInput = struct( ...
                'action',        'override', ...
                'graderId',      getReviewerId(app), ...
                'overrideGrade', overrideGrade, ...
                'notes',         char(app.ReviewerNotesField.Value));

            try
                review = submitReview(app.Case, reviewerInput, app.Config);
                app.Case.review = review;
                app.ReviewComplete = true;
                updateReviewStatus(app, review);
                setStatus(app, sprintf('Grade overridden to %d (%s).', ...
                    overrideGrade, app.GRADE_LABELS{overrideGrade + 1}));
            catch ME
                setStatus(app, sprintf('Override failed: %s', ME.message));
            end
        end

        function onRecapture(app, ~, ~)
        %ONRECAPTURE  Handle recapture button press.
            if isempty(app.Case)
                setStatus(app, 'No case loaded.');
                return;
            end

            reviewerInput = struct( ...
                'action',        'recapture', ...
                'graderId',      getReviewerId(app), ...
                'overrideGrade', NaN, ...
                'notes',         char(app.ReviewerNotesField.Value));

            try
                review = submitReview(app.Case, reviewerInput, app.Config);
                app.Case.review = review;
                app.ReviewComplete = true;
                updateReviewStatus(app, review);
                setStatus(app, 'Recapture requested. Original analysis preserved.');
            catch ME
                setStatus(app, sprintf('Recapture failed: %s', ME.message));
            end
        end

        function onGenerateReport(app, ~, ~)
        %ONGENERATEREPORT  Generate report from current case.
            if isempty(app.Case) || ~isfield(app.Case, 'grading')
                setStatus(app, 'No case loaded.');
                return;
            end

            setStatus(app, 'Generating report...');
            try
                % Build report
                app.Case.report = buildReport(app.Case, app.Config);

                % Render report
                app.Case.report.filepath = renderReport(app.Case.report, ...
                    struct('out', paths().output));

                app.CurrentReport = app.Case.report;
                setStatus(app, sprintf('Report generated: %s', app.Case.report.filepath));
            catch ME
                setStatus(app, sprintf('Report generation failed: %s', ME.message));
            end
        end

        function onOpenReport(app, ~, ~)
        %ONOPENREPORT  Open the generated report file.
            if ~isempty(app.CurrentReport) && isfield(app.CurrentReport, 'filepath') && ...
                    ~isempty(app.CurrentReport.filepath) && exist(app.CurrentReport.filepath, 'file')
                try
                    open(app.CurrentReport.filepath);
                    setStatus(app, 'Report opened.');
                catch ME
                    setStatus(app, sprintf('Could not open report: %s', ME.message));
                end
            else
                setStatus(app, 'No report available. Generate report first.');
            end
        end
    end

    % ---- UI update methods ----
    methods (Access = private)

        function updateImagePanel(app)
        %UPDATEIMAGEPANEL  Display the original retinal image.
            if isempty(app.Case) || ~isfield(app.Case, 'image') || isempty(app.Case.image)
                return;
            end

            img = app.Case.image;
            imshow(img, 'Parent', app.ImageAxes);
            title(app.ImageAxes, 'Original Retinal Image', 'FontSize', 10);
        end

        function updateScreeningResult(app)
        %UPDATESCREENINGRESULT  Populate screening result panel.
            c = app.Case;

            % Patient info
            app.PatientLabel.Text = sprintf('Patient: %s | Eye: %s', ...
                c.meta.patientId, c.meta.eye);

            % Quality
            qClass = c.quality.class;
            qColor = getQualityColor(qClass);
            app.QualityLabel.Text = sprintf('Quality: %s (%.2f)', ...
                upper(qClass), c.quality.score);
            app.QualityLabel.FontColor = qColor;

            % DR Grade
            if ~isnan(c.grading.grade)
                gradeIdx = c.grading.grade + 1;
                gradeLabel = app.GRADE_LABELS{gradeIdx};
                app.GradeLabel.Text = sprintf('DR Grade: %d', c.grading.grade);
                app.GradeDetailLabel.Text = gradeLabel;

                % Color-code by severity
                gradeColors = {[0 0.5 0], [0 0.6 0], [0.8 0.5 0], [0.8 0 0], [0.8 0 0]};
                app.GradeLabel.FontColor = gradeColors{gradeIdx};
                app.GradeDetailLabel.FontColor = gradeColors{gradeIdx};
            else
                app.GradeLabel.Text = 'DR Grade: N/A';
                app.GradeDetailLabel.Text = 'Not graded';
            end

            % Referable
            if c.grading.referable
                app.GradeDetailLabel.Text = [app.GradeDetailLabel.Text, ' (REFERABLE)'];
            end

            % Calibration
            if ~isnan(c.calibrated.confidence)
                app.ConfidenceLabel.Text = sprintf('Confidence: %.1f%%', ...
                    c.calibrated.confidence * 100);
                app.UncertaintyLabel.Text = sprintf('Uncertainty: %.1f%%', ...
                    c.calibrated.uncertainty * 100);
            end

            % Review required
            if c.calibrated.reviewRequired
                app.ReviewReqLabel.Text = 'HUMAN REVIEW REQUIRED';
                app.ReviewReqLabel.FontColor = [0.8 0 0];
                app.ReviewReqLabel.FontWeight = 'bold';
            else
                app.ReviewReqLabel.Text = 'Review: Not required';
                app.ReviewReqLabel.FontColor = [0 0.5 0];
            end

            % Evidence confidence
            if isfield(c.evidence, 'confidence') && ~isempty(c.evidence.confidence)
                app.EvidenceConfLabel.Text = sprintf('Evidence: %s confidence', ...
                    upper(c.evidence.confidence));
                confColors = struct('low', [0.8 0 0], 'medium', [0.8 0.5 0], 'high', [0 0.5 0]);
                app.EvidenceConfLabel.FontColor = confColors.(c.evidence.confidence);
            end
        end

        function updateVisualizationTabs(app)
        %UPDATEVISUALIZATIONTABS  Populate all visualization tabs.
            c = app.Case;

            % ---- Original tab ----
            if ~isempty(c.image)
                imshow(c.image, 'Parent', app.OriginalAxes);
                title(app.OriginalAxes, 'Original Image');
            end

            % ---- Grad-CAM tab ----
            if isfield(c, 'explain') && isstruct(c.explain) && ...
                    isfield(c.explain, 'attentionImage') && ~isempty(c.explain.attentionImage)
                imshow(c.explain.attentionImage, 'Parent', app.GradCAMAxes);
                title(app.GradCAMAxes, 'Model Attention (Grad-CAM)');
            else
                showUnavailable(app.GradCAMAxes, ...
                    'Grad-CAM', ...
                    'Unavailable (no trained model)');
            end

            % ---- Vessels tab ----
            if isfield(c, 'evidence') && isfield(c.evidence, 'vesselMask') && ...
                    ~isempty(c.evidence.vesselMask) && any(c.evidence.vesselMask(:))
                vesselOverlay = createVesselOverlay(c.image, c.evidence.vesselMask);
                imshow(vesselOverlay, 'Parent', app.VesselsAxes);
                title(app.VesselsAxes, 'Vessel Evidence');
            else
                showUnavailable(app.VesselsAxes, ...
                    'Vessel Segmentation', ...
                    'No vessel evidence detected');
            end

            % ---- Structures tab (optic disc + fovea) ----
            if ~isempty(c.image)
                structOverlay = c.image;
                hasOD = false;
                hasFovea = false;

                % Optic disc
                if isfield(c.evidence, 'opticDiscDetail') && isstruct(c.evidence.opticDiscDetail) && ...
                        strcmp(c.evidence.opticDiscDetail.status, 'detected')
                    structOverlay = overlayOpticDisc(structOverlay, c.evidence.opticDiscDetail, ...
                        struct('showCenter', true, 'showBBox', true, 'showConfidence', true));
                    hasOD = true;
                end

                % Fovea
                if isfield(c.evidence, 'fovea') && ~isempty(c.evidence.fovea) && ...
                        numel(c.evidence.fovea) >= 2
                    fv = c.evidence.fovea;
                    fColor = uint8([255 165 0]);  % orange
                    r = 10;
                    structOverlay = insertShape(structOverlay, 'Circle', ...
                        [fv(1), fv(2), r], 'Color', fColor, 'LineWidth', 2, 'Opacity', 0.9);
                    structOverlay = insertText(structOverlay, ...
                        [fv(1) + 15, fv(2) - 5], 'Fovea', ...
                        'FontSize', 12, 'TextColor', uint8([255 255 255]), ...
                        'BoxColor', uint8([0 0 0]), 'BoxOpacity', 0.7);
                    hasFovea = true;
                end

                imshow(structOverlay, 'Parent', app.StructuresAxes);
                titleStr = 'Retinal Structures';
                if hasOD; titleStr = [titleStr, ' (Disc + Fovea)'];
                elseif hasFovea; titleStr = [titleStr, ' (Fovea only)'];
                else; titleStr = [titleStr, ' (Not detected)'];
                end
                title(app.StructuresAxes, titleStr);
            end

            % ---- Lesions tab ----
            updateLesionVisualization(app);
        end

        function updateLesionVisualization(app)
        %UPDATELESIONVISUALIZATION  Create lesion evidence overlay.
            c = app.Case;
            if ~isfield(c, 'image') || isempty(c.image)
                showUnavailable(app.LesionsAxes, 'Lesions', 'No image available');
                return;
            end
            if ~isfield(c, 'evidence') || ~isfield(c.evidence, 'lesions')
                showUnavailable(app.LesionsAxes, 'Lesions', 'No lesion evidence available');
                return;
            end

            img = c.image;
            overlay = img;

            % Color coding for lesion classes
            lesionColors = struct( ...
                'exudates',       uint8([255 255 0]), ...   % Yellow
                'hemorrhages',    uint8([255 0 0]), ...     % Red
                'microaneurysms', uint8([255 0 255]), ...   % Magenta
                'neoVasc',        uint8([0 255 255]));      % Cyan

            classes = fieldnames(lesionColors);
            hasAny = false;

            for i = 1:numel(classes)
                cls = classes{i};
                if isfield(c.evidence.lesions, cls)
                    les = c.evidence.lesions.(cls);
                    if isstruct(les) && isfield(les, 'map') && ~isempty(les.map) && any(les.map(:))
                        color = lesionColors.(cls);
                        for ch = 1:3
                            channel = overlay(:,:,ch);
                            channel(les.map) = color(ch);
                            overlay(:,:,ch) = channel;
                        end
                        hasAny = true;
                    end
                end
            end

            if ~hasAny
                showUnavailable(app.LesionsAxes, ...
                    'Lesion Candidates', ...
                    'No candidate evidence detected');
            else
                imshow(overlay, 'Parent', app.LesionsAxes);
                title(app.LesionsAxes, 'Lesion Candidate Evidence');
            end
        end

        function updateLesionEvidence(app)
        %UPDATELESIONEVIDENCE  Update lesion count labels.
            c = app.Case;
            if ~isfield(c, 'evidence') || ~isfield(c.evidence, 'lesions')
                app.ExudatesLabel.Text = 'Exudates: N/A';
                app.HemorrhagesLabel.Text = 'Hemorrhages: N/A';
                app.MicroaneurysmsLabel.Text = 'Microaneurysms: N/A';
                app.NeoVascLabel.Text = 'NeoVasc: N/A';
                return;
            end

            les = c.evidence.lesions;

            app.ExudatesLabel.Text = formatLesionCount(les.exudates, 'Exudates');
            app.HemorrhagesLabel.Text = formatLesionCount(les.hemorrhages, 'Hemorrhages');
            app.MicroaneurysmsLabel.Text = formatLesionCount(les.microaneurysms, 'Microaneurysms');
            app.NeoVascLabel.Text = formatLesionCount(les.neoVasc, 'NeoVasc');

            % Color-code by presence
            app.ExudatesLabel.FontColor = getLesionColor(les.exudates.count > 0);
            app.HemorrhagesLabel.FontColor = getLesionColor(les.hemorrhages.count > 0);
            app.MicroaneurysmsLabel.FontColor = getLesionColor(les.microaneurysms.count > 0);
            app.NeoVascLabel.FontColor = getLesionColor(les.neoVasc.count > 0);
        end

        function updateReviewControls(app)
        %UPDATEREVIEWCONTROLS  Enable/disable review controls based on state.
            c = app.Case;

            % Reset review state
            app.ReviewComplete = false;
            app.OverrideGradeDropdown.Value = 'Select grade (0-4)...';
            app.ReviewerNotesField.Value = '';
            if ~isempty(app.ReviewerId)
                app.ReviewerIdField.Value = app.ReviewerId;
            end

            % Show current review status
            if isfield(c, 'review') && isfield(c.review, 'status')
                switch c.review.status
                    case 'auto'
                        app.StatusLabel.Text = 'Status: Pending Review';
                        app.StatusLabel.FontColor = [0.5 0.5 0.5];
                    case 'approved'
                        app.StatusLabel.Text = 'Status: Approved';
                        app.StatusLabel.FontColor = [0 0.5 0];
                    case 'overridden'
                        app.StatusLabel.Text = sprintf('Status: Overridden (grade %d)', ...
                            c.review.overrideGrade);
                        app.StatusLabel.FontColor = [0 0.5 0];
                    case 'reqReview'
                        app.StatusLabel.Text = 'Status: Awaiting Review';
                        app.StatusLabel.FontColor = [0.8 0.5 0];
                    otherwise
                        app.StatusLabel.Text = sprintf('Status: %s', c.review.status);
                        app.StatusLabel.FontColor = [0 0 0];
                end
            else
                app.StatusLabel.Text = 'Status: Pending Review';
                app.StatusLabel.FontColor = [0.5 0.5 0.5];
            end

            % Disable buttons if review already complete
            if app.ReviewComplete
                app.ApproveButton.Enable = 'off';
                app.OverrideButton.Enable = 'off';
                app.RecaptureButton.Enable = 'off';
            else
                app.ApproveButton.Enable = 'on';
                app.OverrideButton.Enable = 'on';
                app.RecaptureButton.Enable = 'on';
            end
        end

        function updateReviewStatus(app, review)
        %UPDATEREVIEWSTATUS  Update UI after review action.
            switch review.action
                case 'approve'
                    app.StatusLabel.Text = 'Status: APPROVED';
                    app.StatusLabel.FontColor = [0 0.5 0];
                case 'override'
                    app.StatusLabel.Text = sprintf('Status: OVERRIDDEN (grade %d -> %d)', ...
                        app.Case.grading.grade, review.overrideGrade);
                    app.StatusLabel.FontColor = [0 0.5 0];
                case 'recapture'
                    app.StatusLabel.Text = 'Status: RECAPTURE REQUIRED';
                    app.StatusLabel.FontColor = [0.8 0.5 0];
                otherwise
                    app.StatusLabel.Text = sprintf('Status: %s', review.status);
            end

            % Disable review buttons after action
            app.ApproveButton.Enable = 'off';
            app.OverrideButton.Enable = 'off';
            app.RecaptureButton.Enable = 'off';
        end
    end

    % ---- Layout builder ----
    methods (Access = private)

        function buildLayout(app)
        %BUILDLAYOUT  Construct the full application layout.
            % ---- Main figure ----
            app.Fig = uifigure('Name', 'RetinaSense — Retinal Screening Review', ...
                'Position', [100 100 1400 900], ...
                'Resize', 'on', ...
                'Color', [0.95 0.95 0.97], ...
                'DeleteFcn', @(~,~) delete(app));

            % ---- Top bar (title + status) ----
            app.TopBar = uipanel(app.Fig, ...
                'Position', [0 860 1400 40], ...
                'BackgroundColor', [0.1 0.2 0.4], ...
                'BorderType', 'none');

            uilabel(app.TopBar, ...
                'Text', 'RETINASENSE', ...
                'Position', [20 8 200 24], ...
                'FontColor', [1 1 1], ...
                'FontSize', 16, ...
                'FontWeight', 'bold');

            uilabel(app.TopBar, ...
                'Text', 'Retinal Screening Review System — Decision Support Interface', ...
                'Position', [220 8 500 24], ...
                'FontColor', [0.7 0.8 1], ...
                'FontSize', 12);

            app.StatusFieldLabel = uilabel(app.TopBar, ...
                'Text', 'No case loaded', ...
                'Position', [1050 8 340 24], ...
                'FontColor', [0.7 0.8 1], ...
                'FontSize', 11, ...
                'HorizontalAlignment', 'right');

            % ---- Left panel: original image ----
            app.LeftPanel = uipanel(app.Fig, ...
                'Position', [10 280 450 570], ...
                'Title', 'Retinal Image', ...
                'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.98 0.98 1], ...
                'HighlightColor', [0.1 0.2 0.4]);

            app.ImageAxes = uiaxes(app.LeftPanel, ...
                'Position', [10 10 430 520], ...
                'Box', 'off', ...
                'XTick', [], ...
                'YTick', []);

            % ---- Right panel: screening result ----
            app.RightPanel = uipanel(app.Fig, ...
                'Position', [470 280 470 570], ...
                'Title', 'Screening Result', ...
                'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.98 0.98 1], ...
                'HighlightColor', [0.1 0.2 0.4]);

            buildScreeningPanel(app);

            % ---- Center panel: visualization tabs ----
            app.CenterPanel = uipanel(app.Fig, ...
                'Position', [950 280 440 570], ...
                'Title', 'Evidence / Explainability', ...
                'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.98 0.98 1], ...
                'HighlightColor', [0.1 0.2 0.4]);

            buildVisualizationTabs(app);

            % ---- Bottom panel: review controls ----
            app.BottomPanel = uipanel(app.Fig, ...
                'Position', [10 10 1380 260], ...
                'Title', 'Human Review', ...
                'FontSize', 11, ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.95 0.97 1], ...
                'HighlightColor', [0.1 0.2 0.4]);

            buildReviewPanel(app);
        end

        function buildScreeningPanel(app)
        %BUILDSCREENINGPANEL  Create the screening result labels.
            yStart = 490;
            lineH = 30;
            xL = 15;
            xR = 200;

            % Patient
            app.PatientLabel = makeLabel(app.RightPanel, ...
                'Patient: ---', xL, yStart, 440, 'bold');

            yStart = yStart - lineH - 10;

            % Quality
            app.QualityLabel = makeLabel(app.RightPanel, ...
                'Quality: ---', xL, yStart, 440, 'normal');

            yStart = yStart - lineH - 15;

            % DR Grade header
            makeLabel(app.RightPanel, 'DR GRADE', xL, yStart, 440, 'bold');

            yStart = yStart - lineH;
            app.GradeLabel = makeLabel(app.RightPanel, ...
                'DR Grade: ---', xL, yStart, 200, 'bold', 18);

            yStart = yStart - lineH;
            app.GradeDetailLabel = makeLabel(app.RightPanel, ...
                '---', xL, yStart, 200, 'normal', 14);

            yStart = yStart - lineH - 15;

            % Calibration
            makeLabel(app.RightPanel, 'CALIBRATION', xL, yStart, 440, 'bold');

            yStart = yStart - lineH;
            app.ConfidenceLabel = makeLabel(app.RightPanel, ...
                'Confidence: ---', xL, yStart, 250, 'normal');

            yStart = yStart - lineH;
            app.UncertaintyLabel = makeLabel(app.RightPanel, ...
                'Uncertainty: ---', xL, yStart, 250, 'normal');

            yStart = yStart - lineH - 5;

            app.ReviewReqLabel = makeLabel(app.RightPanel, ...
                '---', xL, yStart, 440, 'normal');

            yStart = yStart - lineH - 15;

            % Evidence
            makeLabel(app.RightPanel, 'EVIDENCE', xL, yStart, 440, 'bold');

            yStart = yStart - lineH;
            app.EvidenceConfLabel = makeLabel(app.RightPanel, ...
                'Evidence: ---', xL, yStart, 440, 'normal');
        end

        function buildVisualizationTabs(app)
        %BUILDVISUALIZATIONTABS  Create the evidence tab group.
            app.VizTabGroup = uitabgroup(app.CenterPanel, ...
                'Position', [10 10 420 520]);

            % Original
            app.OriginalTab = uitab(app.VizTabGroup, 'Title', 'Original');
            app.OriginalAxes = uiaxes(app.OriginalTab, ...
                'Position', [5 5 405 480], ...
                'Box', 'off', 'XTick', [], 'YTick', []);

            % Grad-CAM
            app.GradCAMTab = uitab(app.VizTabGroup, 'Title', 'Grad-CAM');
            app.GradCAMAxes = uiaxes(app.GradCAMTab, ...
                'Position', [5 5 405 480], ...
                'Box', 'off', 'XTick', [], 'YTick', []);

            % Vessels
            app.VesselsTab = uitab(app.VizTabGroup, 'Title', 'Vessels');
            app.VesselsAxes = uiaxes(app.VesselsTab, ...
                'Position', [5 5 405 480], ...
                'Box', 'off', 'XTick', [], 'YTick', []);

            % Structures
            app.StructuresTab = uitab(app.VizTabGroup, 'Title', 'Structures');
            app.StructuresAxes = uiaxes(app.StructuresTab, ...
                'Position', [5 5 405 480], ...
                'Box', 'off', 'XTick', [], 'YTick', []);

            % Lesions
            app.LesionsTab = uitab(app.VizTabGroup, 'Title', 'Lesions');
            app.LesionsAxes = uiaxes(app.LesionsTab, ...
                'Position', [5 5 405 480], ...
                'Box', 'off', 'XTick', [], 'YTick', []);
        end

        function buildReviewPanel(app)
        %BUILDREVIEWPANEL  Create the human review controls.
            yStart = 210;
            lineH = 28;

            % ---- Status ----
            app.StatusLabel = makeLabel(app.BottomPanel, ...
                'Status: Pending Review', 20, yStart, 350, 'bold', 12);
            app.StatusLabel.FontColor = [0.5 0.5 0.5];

            % ---- Reviewer ID ----
            makeLabel(app.BottomPanel, 'Reviewer ID:', 20, yStart - lineH - 5, 80, 'normal');
            app.ReviewerIdField = uieditfield(app.BottomPanel, 'text', ...
                'Position', [110 yStart - lineH - 5 150 22], ...
                'Value', app.ReviewerId, ...
                'Placeholder', 'e.g. OPH-01');

            % ---- Action buttons ----
            btnY = yStart - 2 * lineH - 10;
            btnW = 130;
            btnH = 40;
            btnGap = 15;
            btnX = 20;

            % Approve
            app.ApproveButton = uibutton(app.BottomPanel, 'push', ...
                'Text', 'APPROVE', ...
                'Position', [btnX btnY btnW btnH], ...
                'FontWeight', 'bold', ...
                'FontSize', 12, ...
                'BackgroundColor', [0.2 0.6 0.2], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) onApprove(app));

            % Override
            btnX = btnX + btnW + btnGap;
            app.OverrideButton = uibutton(app.BottomPanel, 'push', ...
                'Text', 'OVERRIDE GRADE', ...
                'Position', [btnX btnY btnW btnH], ...
                'FontWeight', 'bold', ...
                'FontSize', 11, ...
                'BackgroundColor', [0.8 0.5 0], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) onOverride(app));

            % Override grade selector
            btnX = btnX + btnW + btnGap;
            app.OverrideGradeLabel = makeLabel(app.BottomPanel, ...
                'Override to:', btnX, btnY + 10, 80, 'normal');
            app.OverrideGradeDropdown = uidropdown(app.BottomPanel, ...
                'Items', {'Select grade (0-4)...', ...
                          '0 - No DR', ...
                          '1 - Mild NPDR', ...
                          '2 - Moderate NPDR', ...
                          '3 - Severe NPDR', ...
                          '4 - Proliferative DR'}, ...
                'Value', 'Select grade (0-4)...', ...
                'Position', [btnX + 80 btnY + 5 170 30]);

            % Recapture
            btnX = btnX + 80 + 170 + btnGap;
            app.RecaptureButton = uibutton(app.BottomPanel, 'push', ...
                'Text', 'RECAPTURE', ...
                'Position', [btnX btnY btnW btnH], ...
                'FontWeight', 'bold', ...
                'FontSize', 12, ...
                'BackgroundColor', [0.6 0.2 0.2], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) onRecapture(app));

            % ---- Reviewer notes ----
            notesY = btnY - lineH - 15;
            makeLabel(app.BottomPanel, 'Reviewer Notes:', 20, notesY, 120, 'normal');
            app.ReviewerNotesField = uitextarea(app.BottomPanel, ...
                'Position', [140 notesY - 35 600 55], ...
                'Value', '', ...
                'Placeholder', 'Enter review notes here...');

            % ---- Report buttons ----
            reportX = 760;
            app.GenerateReportButton = uibutton(app.BottomPanel, 'push', ...
                'Text', 'Generate Report', ...
                'Position', [reportX notesY - 10 140 30], ...
                'FontSize', 10, ...
                'BackgroundColor', [0.3 0.4 0.6], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) onGenerateReport(app));

            app.OpenReportButton = uibutton(app.BottomPanel, 'push', ...
                'Text', 'Open Report', ...
                'Position', [reportX + 150 notesY - 10 120 30], ...
                'FontSize', 10, ...
                'BackgroundColor', [0.4 0.5 0.6], ...
                'FontColor', [1 1 1], ...
                'ButtonPushedFcn', @(~,~) onOpenReport(app));

            % ---- Disclaimer ----
            disclaimerY = 5;
            uilabel(app.BottomPanel, ...
                'Text', app.DISCLAIMER, ...
                'Position', [20 disclaimerY 700 20], ...
                'FontSize', 8, ...
                'FontColor', [0.5 0.5 0.5], ...
                'FontAngle', 'italic');

            % ---- Grad-CAM note ----
            uilabel(app.BottomPanel, ...
                'Text', app.ATTENTION_NOTE, ...
                'Position', [20 disclaimerY + 18 700 20], ...
                'FontSize', 8, ...
                'FontColor', [0.5 0.5 0.5], ...
                'FontAngle', 'italic');

            % ---- Lesion candidate note (candidate evidence, not diagnosis) ----
            uilabel(app.BottomPanel, ...
                'Text', app.CANDIDATE_NOTE, ...
                'Position', [20 disclaimerY + 36 700 20], ...
                'FontSize', 8, ...
                'FontColor', [0.5 0.5 0.5], ...
                'FontAngle', 'italic');
        end
    end

    % ---- Helper methods ----
    methods (Access = private)

        function id = getReviewerId(app)
        %GETREVIEWERID  Get the reviewer ID from the UI field.
            id = char(app.ReviewerIdField.Value);
            if isempty(id)
                id = 'anonymous';
            end
        end

        function setStatus(app, msg)
        %SETSTATUS  Update the status bar message.
            app.StatusFieldLabel.Text = msg;
        end

        function showUnavailable(~, ax, titleStr, msg)
        %SHOWUNAVAILABLE  Display an unavailable message on an axes.
            cla(ax);
            text(ax, 0.5, 0.5, msg, ...
                'Units', 'normalized', ...
                'HorizontalAlignment', 'center', ...
                'FontSize', 14, ...
                'Color', [0.5 0.5 0.5], ...
                'FontAngle', 'italic');
            title(ax, titleStr);
            ax.XLim = [0 1];
            ax.YLim = [0 1];
            ax.XTick = [];
            ax.YTick = [];
        end
    end
end

% ========================================================================
%  MODULE-LEVEL HELPER FUNCTIONS
% ========================================================================

function lbl = makeLabel(parent, text, x, y, w, style, fontSize)
%MAKELABEL  Create a standardized label in a panel.
    if nargin < 7; fontSize = 10; end
    if nargin < 6; style = 'normal'; end

    fontWeight = 'normal';
    if strcmp(style, 'bold'); fontWeight = 'bold'; end

    lbl = uilabel(parent, ...
        'Text', text, ...
        'Position', [x y w 22], ...
        'FontSize', fontSize, ...
        'FontWeight', fontWeight, ...
        'VerticalAlignment', 'middle');
end

function color = getQualityColor(qClass)
%GETQUALITYCOLOR  Return color for quality class.
    switch lower(qClass)
        case 'good'
            color = [0 0.5 0];
        case 'borderline'
            color = [0.8 0.5 0];
        case 'ungradable'
            color = [0.8 0 0];
        otherwise
            color = [0.5 0.5 0.5];
    end
end

function color = getLesionColor(hasCandidates)
%GETLESIONCOLOR  Return color based on lesion candidate presence.
    if hasCandidates
        color = [0.8 0.4 0];
    else
        color = [0.5 0.5 0.5];
    end
end

function txt = formatLesionCount(lesion, label)
%FORMATLESIONCOUNT  Format a lesion count label with safety language.
    if isstruct(lesion) && isfield(lesion, 'count')
        if lesion.count > 0
            txt = sprintf('%s: %d candidate(s)', label, lesion.count);
        else
            txt = sprintf('%s: No candidates', label);
        end
    else
        txt = sprintf('%s: N/A', label);
    end
end

function overlay = createVesselOverlay(image, vesselMask)
%CREATEVESSELOVERLAY  Overlay vessel mask on the original image.
%   Creates a green-tinted overlay showing detected vessel candidates.

    if isempty(image) || isempty(vesselMask)
        overlay = image;
        return;
    end

    overlay = image;

    % Ensure vesselMask is logical
    vm = logical(vesselMask);

    if ~any(vm(:))
        return;
    end

    % Create green channel overlay
    for ch = 1:3
        channel = overlay(:,:,ch);
        if ch == 2  % green channel: enhance
            channel(vm) = min(255, double(channel(vm)) + 100);
        else  % red/blue: reduce to create green tint
            channel(vm) = max(0, double(channel(vm)) * 0.5);
        end
        overlay(:,:,ch) = uint8(channel);
    end
end
