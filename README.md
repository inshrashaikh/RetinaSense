# RetinaSense

AI-assisted screening decision-support for diabetic retinopathy (DR), from a single fundus photo to an ophthalmologist-approved referral decision.

## Overview

RetinaSense ingests a fundus image, runs a deterministic image-quality gate, grades DR severity (0–4) with a trained CNN, and presents calibrated confidence plus a Grad-CAM attention map to an ophthalmologist for the final referral decision. A parallel Simulink/SimEvents model simulates district-level workflow capacity to assess whether a screening node can sustain large patient volumes.

## Key Features

- **Image quality assessment + enhancement** — classifies images as good/borderline/ungradable, routes borderline frames through enhancement and re-check, and explains *how* to recapture a rejected image.
- **Retinal/lesion analysis** — advisory vessel, optic-disc, fovea, and lesion-candidate analysis that never blocks grading.
- **DR grading 0–4** — CNN-based five-class severity grading with referable-DR decision (grade ≥ 2).
- **Grad-CAM + calibrated confidence** — attention maps from the trained model plus temperature-scaled confidence/uncertainty that routes low-confidence cases to mandatory human review.
- **Human-in-the-loop doctor review** — ophthalmologist approves, overrides, or requests recapture; the AI prediction is never silently overwritten.
- **PDF reporting** — case reports are generated and exported as PDF.
- **District simulation** — a Simulink/SimEvents model measures full-workday district workflow capacity across reviewer/bandwidth/load scenarios.

## Architecture

```
Image → Quality Gate ──borderline──→ Enhance → Re-check ──→ passed
         │ ungradable                              │
         └→ Recapture feedback (exit early)        │
                         passed ←──────────────────┘
                → Retinal/Lesion Analysis (advisory)
                → DR Grading (0–4, referable = Level 2+)
                → Grad-CAM + Calibrated confidence/uncertainty
                → Human Review (approve / override / recapture)
                → Report + referral decision
```

Each stage implements a single stable contract operating on a shared `Case` structure, orchestrated by `scripts/runPipeline.m`. See `docs/ARCHITECTURE.md`.

## Tech Stack

- **MATLAB** with **Image Processing Toolbox**, **Computer Vision Toolbox**, **Deep Learning Toolbox**, **Medical Imaging Toolbox**, **Statistics and Machine Learning Toolbox**
- **Simulink** + **SimEvents** for district workflow simulation
- **Python** + **FastAPI** backend, bridging to MATLAB via the **MATLAB Engine for Python**
- **React**, **TypeScript**, **Vite** frontend with a three-role (operator / doctor / admin) UI
- **SQLite** for case, review, and report persistence
- **PyTorch** and **ONNX** model artifacts

## Current Status

- Working research/engineering prototype.
- The end-to-end workflow has been tested with real data and real trained model/calibration artifacts (APTOS images through the full MATLAB pipeline, live backend–frontend flow, real Simulink scenario output).
- **Not clinically validated and not production-ready.**
- Clinical validation and some benchmark targets (e.g., referable sensitivity/specificity) are still pending.

## Data & Model Availability

The datasets (APTOS, IDRiD) and trained model artifacts are intentionally **not committed** to Git due to size and biomedical licensing. The full source code is present and runs the honest mock path without dependencies, but a fresh clone cannot execute the complete AI pipeline until those external assets are restored and a MATLAB environment with the required toolboxes is available.

## Limitations

- Not clinically validated; requires prospective clinical validation before use.
- External validation on independent datasets (e.g., Messidor-2) is still outstanding.
- Current performance targets are not yet confirmed by a final evaluation run.
- District-capacity results, while measured end-to-end, still require further optimization to reach the annual-volume target.