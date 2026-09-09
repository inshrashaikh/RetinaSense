# Optic Disc Localization — Implementation Summary

## Overview
This document describes the implementation of the **Optic Disc Localization** feature (Stage 5b) for RetinaSense, following the existing architecture and conventions.

---

## Method Used

**Classical CV: Bright Temporal-Side Region Detection via Morphology + Connected Component Analysis**

1. **Green Channel Extraction** — The green channel of the fundus image provides the best contrast for optic disc visualization.

2. **FOV Masking** — Excludes dark background pixels (intensity < 0.05) to focus analysis on the retinal region.

3. **Morphological Top-Hat Transform** — Enhances bright, disk-like structures using a disk-shaped structuring element (configurable radius, default 15px).

4. **Adaptive Thresholding** — Candidates are thresholded at a fraction (default 15%) of the maximum top-hat response within the FOV.

5. **Morphological Cleanup** — Opening and closing remove noise; hole-filling ensures solid candidate regions.

6. **Connected Component Analysis** — Each candidate region is analyzed for:
   - **Area** — Constrained to plausible disc size range (configurable min/max as fraction of image area)
   - **Circularity** — 4π×area/perimeter² ≥ threshold (default 0.4)
   - **Brightness** — Mean intensity in green channel
   - **Temporal Proximity** — Bias toward temporal side (default 60% from left for right eye)

7. **Scoring & Selection** — Weighted combination: 40% brightness + 30% temporal proximity + 20% size appropriateness + 10% circularity.

8. **Template Matching Fallback** — If morphology fails, normalized cross-correlation with a circular disk template is attempted.

---

## Inputs

| Parameter | Source | Description |
|-----------|--------|-------------|
| `image` | `Case.image` | H×W×3 uint8 working image (quality-gated, downscaled ≤1024px) |
| `params` | `config/analysis_config.m → opticDisc` | All thresholds, method selection, fallback toggles |

### Key Configurable Parameters (`config/analysis_config.m`)

```matlab
opticDisc.method                    = 'morphology_bright_temporal';
opticDisc.minDiscDiameterPx         = 40;
opticDisc.maxDiscDiameterPx         = 180;
opticDisc.temporalSideBias          = 0.6;          % right-eye temporal side
opticDisc.morphology.diskRadius     = 15;
opticDisc.morphology.topHatThreshold = 0.15;
opticDisc.morphology.minAreaFraction = 0.001;
opticDisc.morphology.maxAreaFraction = 0.03;
opticDisc.circularityThreshold      = 0.4;
opticDisc.confidenceThresholds.high  = 0.75;
opticDisc.confidenceThresholds.medium = 0.40;
opticDisc.fallbackToTemplate        = true;
```

---

## Outputs

The function `locateOpticDisc(image, params)` returns a **struct** with:

| Field | Type | Description |
|-------|------|-------------|
| `center` | `[x, y]` double \| `[]` | Pixel coordinates of disc centre (empty if not detected) |
| `bbox` | `[x, y, w, h]` double \| `[]` | Bounding box of detected region |
| `confidence` | double ∈ [0, 1] | Detection confidence score |
| `status` | `'detected' \| 'low_confidence' \| 'not_detected'` | Discrete status from confidence thresholds |
| `method` | string | `'morphology_bright_temporal'` or `'template_fallback'` |
| `note` | string | Human-readable advisory note |

### Integration into `Case.evidence`

| Field | Type | Description |
|-------|------|-------------|
| `evidence.opticDisc` | `[x, y]` \| `[]` | **Contract-compliant** centre coordinate (backward compatible) |
| `evidence.opticDiscDetail` | struct | Full localization result (for visualization/reporting) |
| `evidence.confidence` | `'low' \| 'medium' \| 'high'` | Aggregated advisory confidence (includes disc detection) |

---

## Failure Behavior

| Condition | Behavior |
|-----------|----------|
| No bright structures in FOV | Returns `status='not_detected'`, `center=[]`, tries template fallback if enabled |
| No components in size range | Same as above |
| No components with sufficient circularity | Same as above |
| Low confidence after scoring | `status='low_confidence'` or `'not_detected'`; `center` may be empty |
| Template fallback fails | Logged in `note`; original morphology result retained |
| Invalid input image | Returns honest empty result with explanatory `note` |

**Critical:** Optic disc localization is **advisory and non-blocking**. Failure to detect the disc:
- Does **not** block DR grading
- Does **not** trigger recapture
- Returns honest low-confidence state
- Pipeline continues normally with `evidence.confidence='low'`

---

## Visualization Overlay

**Function:** `overlayOpticDisc(image, opticDiscDetail, options)`

### Features
- Green crosshair + circle at disc centre
- Yellow bounding box around disc region
- Text overlay showing status, confidence, and method
- Handles `'not_detected'` state with status text

### Options (all optional)
```matlab
options.showCenter       = true;
options.showBBox         = true;
options.showConfidence   = true;
options.centerColor      = [0, 255, 0];   % green
options.bboxColor        = [255, 255, 0]; % yellow
options.textColor        = [255, 255, 255]; % white
options.lineWidth        = 2;
options.centerRadius     = 8;
```

### Integration
The overlay is automatically composed into `Case.explain.evidenceOverlay` by `computeGradCAM.m` when `evidence.opticDiscDetail` is present.

---

## Files Changed

| File | Change Type | Description |
|------|-------------|-------------|
| `config/analysis_config.m` | **New** | Central configuration for all Stage 5 analysis (optic disc, vessels, fovea, lesions) |
| `config/experiment_config.m` | **Modified** | Added `cfg.analysis = analysis_config();` |
| `analysis/locateOpticDisc.m` | **Rewritten** | Full classical CV implementation with morphology + CC analysis + template fallback |
| `analysis/locateFovea.m` | **Rewritten** | Geometric derivation from optic disc + darkest-region fallback |
| `analysis/buildEvidence.m` | **Modified** | Aggregates per-detector confidence; passes through `opticDiscDetail` |
| `analysis/analyzeRetina.m` | **Modified** | Passes config subsections; chains disc→fovea |
| `analysis/overlayOpticDisc.m` | **New** | Visualization overlay for disc detection |
| `explainability/computeGradCAM.m` | **Modified** | Includes optic disc overlay in `evidenceOverlay` |
| `scripts/runPipeline.m` | **Modified** | Passes `cfg.analysis` to `analyzeRetina`; fallback evidence includes `opticDiscDetail` |
| `scripts/demo_mock_pipeline.m` | **Modified** | Shows optic disc status in summary |
| `core/newCase.m` | **Modified** | Added `opticDiscDetail` to default `evidence` struct |
| `tests/unit/test_analysis_modules.m` | **New** | Contract tests for all analysis modules |
| `tests/unit/test_module_interfaces.m` | **Modified** | Extended `test_analyzeRetinaAdvisoryContract` to verify `opticDiscDetail` |
| `tools/python_verifier/mock_pipeline.py` | **Modified** | Mirrors `opticDiscDetail` in evidence schema |

---

## Testing

### Unit Tests (`tests/unit/test_analysis_modules.m`)
- `test_locateOpticDiscContract` — Verifies struct fields, status values, confidence bounds
- `test_locateOpticDiscHandlesInvalidInput` — Empty/non-RGB/wrong-channel images
- `test_locateOpticDiscDeterministic` — Same input → same output
- `test_locateOpticDiscWithConfigVariation` — Temporal bias variation
- `test_locateFoveaContract` — With/without disc input
- `test_buildEvidenceContract` — All fields, confidence levels, `opticDiscDetail`
- `test_overlayOpticDiscBasic` / `test_overlayOpticDiscNotDetected` — Overlay generation
- `test_analyzeRetinaIntegration` — End-to-end analysis stage

### Integration Tests
- Python verifier (`tools/python_verifier/mock_pipeline.py`) — All checks pass
- MATLAB `test_module_interfaces.m` — Contract compliance verified

---

## Medical Safety Compliance

- **Advisory only:** Optic disc localization never blocks grading or triggers recapture
- **No diagnostic claims:** Output is evidence/visualization; `note` field explicitly states "not a diagnosis"
- **Honest failures:** Low confidence or non-detection returned transparently without faked coordinates
- **Deterministic:** Fixed seed, no stochastic components

---

## Future Work (TODO markers in code)

- `TODO(Sprint 7+): refine with validated datasets; add U-Net ablation` in `locateOpticDisc.m`
- `TODO(Sprint 7): classical matched-filter + morphology first; optional U-Net ablation on DRIVE` in `segmentVessels.m`
- `TODO(Sprint 7): top-hat + threshold for exudates...` in `detectLesions.m`
- Confidence aggregation in `buildEvidence.m` currently uses simple detector presence; future: per-detector confidence scores