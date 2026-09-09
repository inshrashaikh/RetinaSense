RetinaSenseApp — Ophthalmologist review interface (Sprint 5, COMPLETE as a programmatic
uifigure reference implementation; the App Designer `.mlapp` packaging is a planned
follow-up, not yet shipped).

Files:
  RetinaSenseApp.m       — programmatic uifigure-based review application (programmatic
                           reference for the planned App Designer/`.mlapp` version)
  launchRetinaSenseApp.m — launcher with graceful fallback

Usage:
  launchRetinaSenseApp('good')
  launchRetinaSenseApp('borderline')
  app = RetinaSenseApp(caseData)

Features:
  - Original retinal image display
  - DR grade + calibrated confidence + review-required status
  - Grad-CAM visualization with safety note
  - Optic disc + fovea visualization
  - Vessel evidence overlay
  - Lesion candidate visualization (4 classes, color-coded)
  - Approve / Override grade / Recapture review controls
  - Reviewer notes + ID
  - Report generation and display

See docs/ARCHITECTURE.md §5 Stage 9 for the design specification.
