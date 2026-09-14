"""
RetinaSense dataset integrity verifier — Python mirror (no MATLAB required).

CI-able mirror of the MATLAB dataset manifest/loader world
(dataset/buildDatasetManifests.m, dataset/loadDataset.m,
dataset/validateDataset.m). It only reports what is actually on disk:

- APTOS: real image count per grade dir + folds.csv split integrity + a small
  bounded sample decode check (3-5 PNGs via Pillow).
- IDRiD: real images/labels/masks/markups as shipped (see data/manifests/
  README.md "IDRiD layout"), counts per sub-task + bounded decode.
- DRIVE / Messidor-2: reports NOT AVAILABLE unless real files exist.

Loader validation PASS here means "real files are structurally sound" — it is
NOT clinical or model validation. Never read a "VALIDATED" status into the
codebase from this script.

Run:  python dataset_check.py
"""

import csv
import os
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]   # repo root
RAW = REPO / "data" / "raw"
MANIFESTS = REPO / "data" / "manifests"

DATASETS = ("aptos", "idrid", "drive", "messidor2")

FAIL = "FAIL"
PASS = "PASS"
NOT_AVAILABLE = "NOT_AVAILABLE"


def _scan_dir(root: Path, exts: tuple) -> tuple:
    """Return (files, ext_count) sorted real files under root."""
    if not root.is_dir():
        return [], {}
    files = sorted(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in exts)
    ext_count = {}
    for p in files:
        ext_count[p.suffix.lower()] = ext_count.get(p.suffix.lower(), 0) + 1
    return files, ext_count


def check_aptos() -> dict:
    images_root = RAW / "aptos" / "images"
    result = {"dataset": "aptos", "status": NOT_AVAILABLE,
              "rows": {}, "folds": None, "decode": None}
    if not images_root.is_dir():
        result["note"] = f"APTOS images root missing: {images_root}"
        return result
    counts = {}
    for g in ("0", "1", "2", "3", "4"):
        gdir = images_root / g
        counts[g] = len([p for p in gdir.glob("*.png") if p.is_file()]) if gdir.is_dir() else 0
    result["rows"] = counts
    total = sum(counts.values())
    result["images"] = total
    result["status"] = PASS if total > 0 else NOT_AVAILABLE

    folds_path = MANIFESTS / "folds.csv"
    if folds_path.is_file():
        rows = list(csv.DictReader(folds_path.open(newline="")))
        split_counts = {}
        sources = set()
        n_dup = len(rows) - len({r["image"] for r in rows})
        for r in rows:
            split_counts[r["split"]] = split_counts.get(r["split"], 0) + 1
            sources.add(r["source"])
        result["folds"] = {
            "n": len(rows),
            "splits": split_counts,
            "sources": sorted(sources),
            "dup_rows": n_dup,
        }
        if n_dup != 0 or sources != {"aptos"}:
            result["status"] = FAIL

    result["decode"] = sample_decode(images_root)
    for (ok, n, msg) in result["decode"]:
        if not ok:
            result["status"] = FAIL
            result["note"] = msg
            break
    return result


def sample_decode(images_root: Path, n: int = 5, exts=(".png",)) -> list:
    """Decode up to n real images with Pillow; must be non-empty valid images."""
    files = sorted(p for p in images_root.rglob("*") if p.is_file() and p.suffix.lower() in exts)
    if not files:
        return [(False, 0, "no image files found")]
    step = max(1, len(files) // n)
    picked = files[::step][:n]
    out = []
    for p in picked:
        try:
            im = Image.open(p)
            im.load()
            ok = im.size[0] > 0 and im.size[1] > 0
            out.append((ok, len(picked), f"{p.relative_to(images_root)} {im.size}"))
        except Exception as exc:  # noqa: BLE001
            out.append((False, len(picked), f"{p.relative_to(images_root)}: {exc}"))
    return out


def check_idrid() -> dict:
    root = RAW / "IDRiD"
    result = {"dataset": "idrid", "source": "IDRiD (IEEE Dataport)", "status": NOT_AVAILABLE}
    if not root.is_dir():
        result["note"] = f"{root} not present. Integration loader prepared but dataset not validated."
        return result

    grad_base = root / "B. Disease Grading" / "B. Disease Grading"
    seg_base = root / "A. Segmentation" / "A. Segmentation"
    loc_base = root / "C. Localization" / "C. Localization"

    # ---- Grading: images + official label CSVs ----
    result["grading"] = {}
    for split_name, sub in (("train", "a. Training Set"), ("test", "b. Testing Set")):
        img_dir = grad_base / "1. Original Images" / sub
        n_imgs = len([p for p in img_dir.glob("*.jpg") if p.is_file()]) if img_dir.is_dir() else 0
        gt_csv = None
        gt_dir = grad_base / "2. Groundtruths"
        if gt_dir.is_dir():
            cands = list(gt_dir.glob(f"*{split_name.capitalize()}*Labels.csv"))
            gt_csv = cands[0] if cands else None
        grades = {}
        rme_counts = {}
        if gt_csv:
            rows = list(csv.DictReader(gt_csv.open(newline="", encoding="utf-8-sig")))
            valid = 0
            for r in rows:
                # Official CSVs carry trailing spaces / filler columns in the
                # header (e.g. "Risk of macular edema "); normalize the keys.
                r = {k.strip(): str(v).strip() for k, v in r.items()}
                if not r.get("Image name") or not r.get("Image name", "").startswith("IDRiD_"):
                    continue  # drop filler rows
                g = r.get("Retinopathy grade", "")
                rm = r.get("Risk of macular edema", "")
                if not (g in ("0", "1", "2", "3", "4") and rm in ("0", "1", "2")):
                    result["status"] = FAIL
                    result["note"] = f"bad {split_name} grade/rme row: {r}"
                    continue
                grades[g] = grades.get(g, 0) + 1
                rme_counts[rm] = rme_counts.get(rm, 0) + 1
                valid += 1
            result["grading"][f"{split_name}_images"] = n_imgs
            result["grading"][f"{split_name}_labels"] = valid
            result["grading"][f"{split_name}_grade_counts"] = dict(sorted(grades.items()))
            result["grading"][f"{split_name}_rme_counts"] = dict(sorted(rme_counts.items()))
            if valid == 0:
                result["status"] = FAIL
                result["note"] = f"{split_name}: grade CSV unreadable"

    # ---- Segmentation: images + real lesion masks ----
    result["segmentation"] = {}
    lesions = {"1. Microaneurysms": "MA", "2. Haemorrhages": "HE",
               "3. Hard Exudates": "EX", "4. Soft Exudates": "SE",
               "5. Optic Disc": "OD"}
    for split_name, sub in (("train", "a. Training Set"), ("test", "b. Testing Set")):
        img_dir = seg_base / "1. Original Images" / sub
        n_imgs = len([p for p in img_dir.glob("*.jpg") if p.is_file()]) if img_dir.is_dir() else 0
        mask_counts = {}
        for lesion_name, suf in lesions.items():
            mask_dir = seg_base / "2. All Segmentation Groundtruths" / sub / lesion_name
            n_mask = len([p for p in mask_dir.glob(f"*_{suf}.tif") if p.is_file()]) if mask_dir.is_dir() else 0
            mask_counts[lesion_name] = n_mask
        result["segmentation"][f"{split_name}_images"] = n_imgs
        result["segmentation"][f"{split_name}_masks"] = mask_counts

    # ---- Localization: images + OD/fovea markups ----
    result["localization"] = {}
    for split_name, sub in (("train", "a. Training Set"), ("test", "b. Testing Set")):
        img_dir = loc_base / "1. Original Images" / sub
        n_imgs = len([p for p in img_dir.glob("*.jpg") if p.is_file()]) if img_dir.is_dir() else 0
        od_n = fo_n = 0
        gt_base = loc_base / "2. Groundtruths"
        od_dir = gt_base / "1. Optic Disc Center Location"
        fo_dir = gt_base / "2. Fovea Center Location"
        for d, match in ((od_dir, "OD_Center"), (fo_dir, "Fovea_Center")):
            if not d.is_dir():
                continue
            cands = [p for p in d.iterdir() if p.suffix == ".csv" and match in p.name]
            if not cands:
                continue
            rows = list(csv.DictReader(cands[0].open(newline="", encoding="utf-8-sig")))
            n = sum(1 for r in rows if str(r.get("Image No", "")).startswith("IDRiD_"))
            if match.startswith("OD"):
                od_n = n
            else:
                fo_n = n
        result["localization"][f"{split_name}_images"] = n_imgs
        result["localization"][f"{split_name}_od_markups"] = od_n
        result["localization"][f"{split_name}_fovea_markups"] = fo_n

    result["images"] = result["grading"]["train_images"] + result["grading"]["test_images"]
    result["decode"] = sample_decode(
        grad_base / "1. Original Images" / "a. Training Set", 3, (".jpg",))
    for (ok, n, msg) in result["decode"]:
        if not ok:
            result["status"] = FAIL
            result["note"] = msg
            break
    if result["status"] == NOT_AVAILABLE:
        result["status"] = PASS
        result["model_validation"] = "NOT PERFORMED (loader-verified structure only)"
        result["note"] = "Real IDRiD files structurally sound; correctness claims, if any, come from evaluation/."
    return result


def check_drive() -> dict:
    root = RAW / "drive"
    result = {"dataset": "drive", "source": "DRIVE (grand-challenge.org)", "status": NOT_AVAILABLE}
    n = 0
    for split_base in ("training", "test"):
        img_dir = root / split_base / "images"
        if img_dir.is_dir():
            files, ext = _scan_dir(img_dir, (".tif", ".png"))
            n += len(files)
            result[f"{split_base}_images"] = len(files)
    result["images"] = n
    result["annotations"] = n  # 1st_manual masks expected paired with images
    result["status"] = PASS if n else NOT_AVAILABLE
    if not n:
        result["note"] = "DRIVE files not present. Integration loader prepared but dataset not validated."
    return result


def check_messidor2() -> dict:
    root = RAW / "messidor2"
    result = {"dataset": "messidor2", "source": "Messidor-2 (official adcis)", "status": NOT_AVAILABLE}
    img_dir = root / "images"
    result["images"] = 0
    if img_dir.is_dir():
        files, ext = _scan_dir(img_dir, (".png", ".jpg", ".jpeg", ".tif"))
        result["images"] = len(files)
        result["extensions"] = ext
    result["labels_present"] = (root / "labels.csv").is_file()
    result["status"] = PASS if result["images"] else NOT_AVAILABLE
    if not result["images"]:
        result["note"] = "Messidor-2 files not present. Integration loader prepared but dataset not validated."
    return result


def main():
    print("RetinaSense dataset integrity check (real files only)\n")
    results = []
    results.append(("aptos", check_aptos))
    results.append(("idrid", check_idrid))
    results.append(("drive", check_drive))
    results.append(("messidor2", check_messidor2))

    ok_all = True
    for name, fn in results:
        r = fn()
        status = r["status"]
        label = status if status == PASS else "FAIL" if status == FAIL else "NOT AVAILABLE"
        print(f"[{label:12}] {name}: " + summarize(r))
        if status != PASS:
            ok_all = False
    print("\nDataset check result:", "FAIL" if not ok_all else "PASS (all real datasets verified)")
    return 0 if ok_all else 1


def summarize(r: dict) -> str:
    if r["status"] == PASS:
        parts = [f"{r.get('images', 0)} images"]
        if "rows" in r:
            parts.insert(0, "grade counts " + str(r["rows"]))
        if r.get("folds"):
            f = r["folds"]
            parts.append(f"folds n={f['n']} splits={f['splits']}")
        if r.get("decode"):
            ok = sum(1 for d in r["decode"] if d[0])
            parts.append(f"decode {ok}/{len(r['decode'])} ok")
        return "; ".join(parts)
    return r.get("note", "unavailable")


if __name__ == "__main__":
    sys.exit(main())