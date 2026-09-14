# Manifests — data split metadata (committed)

Hold the train/val/test/external split tables. These are COMMITTED (they are
small CSVs describing how data is split), while `data/raw` and `data/processed`
are gitignored (biomedical licensing).

Required column schema (docs/ARCHITECTURE.md §8):

| column    | meaning                                   |
|-----------|-------------------------------------------|
| image     | relative path or id of the image          |
| eye_id    | eye token (left/right)                    |
| grade     | ICDR grade 0-4                            |
| split     | train | val | test | external              |
| source    | aptos | idrid | drive | messidor2        |

Rules:
- `messidor2` rows are ONLY ever assigned split=external; never train/val.
- `folds.csv` is the canonical single file for reproducibility (fixed seed).

## Dataset status registry

`dataset_status.csv` (committed, rebuilt by `buildDatasetManifests.m`) records,
per dataset, an honest status chosen from:

| status | meaning |
|--------|---------|
| `AVAILABLE + VALIDATED` | real files on disk AND `validateDataset.m` PASSED on a boundedsample |
| `AVAILABLE + NOT YET VALIDATED` | real files found; validation still pending |
| `CODE ONLY` | loader/manifest logic exists but no dataset files are present |
| `NOT AVAILABLE` | no real files, no loader usable |

Status is NEVER assumed — it is promoted only after files actually exist and a
bounded validation run succeeds.

## Dataset inventory (current)

| dataset | status | purpose | manifests |
|---------|--------|---------|-----------|
| APTOS 2019 | AVAILABLE + NOT YET VALIDATED | DR classifier train/val/test | `aptos_manifest.csv`, `folds.csv` (canonical split) |
| IDRiD | AVAILABLE + NOT YET VALIDATED | DR grade + lesion + optic-disc/fovea validation (external-only) | `idrid_manifest.csv` (+ grading/segmentation/localization) |
| DRIVE | NOT AVAILABLE (loader prepared) | vessel-segmentation validation | `drive_manifest.csv` (empty) |
| Messidor-2 | NOT AVAILABLE (loader prepared) | external DR validation (external-only split) | `messidor2_manifest.csv` (empty) |

## IDRiD layout actually on disk (`data/raw/IDRiD/`, gitignored)

The official IEEE DataPort distribution has three sub-tasks with INDEPENDENT
image sets (verified by hashing — the grading and localization sets are the
same 516 JPEGs; the segmentation set is a separate 81-JPEG download, and its
2-digit IDs are NOT assumed to be the same photos as grading's 3-digit IDs):

```
A. Segmentation/A. Segmentation/
  1. Original Images/{a. Training Set,b. Testing Set}/IDRiD_<NN>.jpg   (54 + 27)
  2. All Segmentation Groundtruths/{a. Training Set,b. Testing Set}/
     {1. Microaneurysms,2. Haemorrhages,3. Hard Exudates,4. Soft Exudates,5. Optic Disc}/
       IDRiD_<NN>_<MA|HE|EX|SE|OD>.tif    (masks sparse per lesion)
B. Disease Grading/B. Disease Grading/
  1. Original Images/{a. Training Set,b. Testing Set}/IDRiD_<NNN>.jpg  (413 + 103)
  2. Groundtruths/*Labels.csv   (Image name, Retinopathy grade 0-4, Risk of macular edema 0-2)
C. Localization/C. Localization/
  1. Original Images/{a. Training Set,b. Testing Set}/IDRiD_<NNN>.jpg  (413 + 103, same photos as B)
  2. Groundtruths/{1. Optic Disc Center Location,2. Fovea Center Location}/*Markups.csv
     (Image No, X- Coordinate, Y - Coordinate — filler rows dropped)
```

The three committed manifests reflect identical real files and relative
paths (no machine-specific absolute paths):
- `idrid_grading_manifest.csv` — image, image_id, grade(0-4), risk_macular_edema, split, source
- `idrid_segmentation_manifest.csv` — image, image_id, split, source, ma/he/ex/se/od_mask ('' when absent)
- `idrid_localization_manifest.csv` — image, image_id, split, source, od_x, od_y, fovea_x, fovea_y
- `idrid_manifest.csv` — master: one row per unique PHYSICAL file (image_id +
  image + split + subset). Grading and localization ship as SEPARATE physical
  copies of the SAME 516 photos, so the master row count (1113 = 516+81+516)
  exceeds the 597 unique photographs; do not treat the two counts as equal.

IDRiD is a VALIDATION dataset for RetinaSense: `prepareClassifierData` only
reads `folds.csv` (APTOS), so IDRiD never joins APTOS training. Status
"AVAILABLE + NOT YET VALIDATED" means files physically load and the bounded
validator passes; NO clinical or model validation has been performed.

## Adding a real dataset (official sources only)

Place official files under `data/raw/<dataset>` (paths in `config/paths.m` →
`cfg.data.datasets`), then run `buildDatasetManifests` to re-scan the real
files, and `validateDataset('<dataset>')` to promote status to `AVAILABLE +
VALIDATED`. Do not fabricate rows; manifests describe real files only.

Official download sources:
- **APTOS 2019** — original Kaggle "APTOS 2019 Blindness Detection" (train
  images + train.csv), redistributed under its competition terms.
- **IDRiD** — IEEE DataPort (Porwal et al.), "Indian Diabetic Retinopathy
  Image Dataset".
- **DRIVE** — grand-challenge.org DRIVE (Digital Retinal Images for Vessel
  Extraction), Staal et al. 2004.
- **Messidor-2** — official ADE-CIS distribution (Decencière et al.), when
  accessing under its research agreement.