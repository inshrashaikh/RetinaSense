# RetinaSense UI — Ophthalmologist review interface (MATLAB)

Programmatic `uifigure`-based review application implementing the
ophthalmologist review interface (design spec in `docs/ARCHITECTURE.md §5
Stage 9`). Serves as both a standalone review tool and the reference
implementation for the review interface.

## Files

- `RetinaSenseApp.m` — programmatic `uifigure`-based review application.
- `launchRetinaSenseApp.m` — launcher with graceful fallback.

## Usage

```matlab
launchRetinaSenseApp()                 % launch with empty state
launchRetinaSenseApp('good')           % launch with mock good case
launchRetinaSenseApp('borderline')     % launch with mock borderline
app = RetinaSenseApp(caseData)         % launch with a populated Case
```

## Features

- Original retinal image display
- DR grade + calibrated confidence + review-required status
- Grad-CAM visualization with safety note
- Optic disc + fovea visualization
- Vessel evidence overlay
- Lesion candidate visualization (4 classes, color-coded)
- Approve / Override grade / Recapture review controls
- Reviewer notes + ID
- Report generation and display

## Layout

- Top bar: title + status
- Left panel: original retinal image
- Right panel: screening result + calibration
- Center: evidence/visualization tab group
- Bottom: human review controls + notes

Consumes the contracts documented in `docs/ARCHITECTURE.md §4`. See
`docs/ARCHITECTURE.md §5 Stage 9` for the design specification.