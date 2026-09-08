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
- Files on this folder are populated once Sprint 2 data preparation lands.
  `folds.csv` currently ships as a schema-only header so integration code can
  parse it from day one.