"""Grad-CAM explainability smoke test (CI-able Python mirror).

Mirror of scripts/runPipeline.m Stage 7 (explainability/computeGradCAM.m).
Uses the SAVED benchmark model (data/models/resnet50_dr_aptos.pt) and a small
APTOS *validation* sample — no training, no test split, no Messidor-2, no
fabricated attention.

Verifies (per docs/ARCHITECTURE.md §4.5):
  - gradCam         HxW×1 double attention heatmap (non-empty for real model)
  - attentionImage  HxWx3 uint8 overlay of heatmap on the original image
  - evidenceOverlay HxWx3 uint8 (honest-empty: no lesion evidence fabricated)
  - note            "Model attention - not proof of causality"
  - Grade 0-4 heatmaps AND referable (grade>=2) heatmaps supported
  - Original image, raw heatmap, and overlay saved as separate artifacts
    under output/artifacts/gradcam/

Run:  python tools/python_verifier/gradcam_smoke_test.py
"""

import json
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from experiment_pipeline import (  # noqa: E402
    DATA_ROOT,
    MANIFEST,
    MODELS_DIR,
    OUTPUT_DIR,
    SEED,
    compute_explain,
    grad_cam_layer,
    load_model,
    load_splits,
    set_seed,
)
from experiment_pipeline import GradCAM  # noqa: E402

MODEL = "resnet50"


def to_rgb_bgr(arr_rgb):
    return cv2.cvtColor(arr_rgb, cv2.COLOR_RGB2BGR)


def save_artifact(out_root, name, arr):
    os.makedirs(out_root, exist_ok=True)
    path = os.path.join(out_root, name)
    if name.lower().endswith(".npy"):
        np.save(path, arr)
    else:
        cv2.imwrite(path, to_rgb_bgr(arr))
    return path


def main():
    set_seed(SEED)
    device = "cpu"

    checkpoint = os.path.join(MODELS_DIR, f"{MODEL}_dr_aptos.pt")
    if not os.path.exists(checkpoint):
        print(f"SKIP: saved model not found ({checkpoint}) - run the benchmark first.")
        return

    model = load_model(MODEL).to(device).eval()
    gcam = GradCAM(model, grad_cam_layer(model, MODEL))

    _, val_df, _, img_root = load_splits(MANIFEST, DATA_ROOT)

    # small grade-balanced sample strictly from VALIDATION (one per grade)
    picked = []
    for g in range(5):
        gv = val_df[val_df["grade"] == g].head(1)
        if len(gv):
            picked.append(gv.iloc[0])

    artifacts_root = os.path.join(OUTPUT_DIR, "artifacts", "gradcam")
    os.makedirs(artifacts_root, exist_ok=True)

    stats = {"gradeCamNonEmpty": 0, "referableCamNonEmpty": 0,
             "gradeCamSized": 0, "referableCamSized": 0, "overlaySized": 0}
    processed = []
    n_total = 0

    for i, row in enumerate(picked):
        img_path = os.path.join(img_root, row["image"])
        frame = cv2.imread(img_path)
        if frame is None:
            print(f"  skip missing image: {img_path}")
            continue
        img_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        H, W = img_rgb.shape[:2]
        n_total += 1

        # model inference -> predicted DR class (not ground truth)
        from experiment_pipeline import transforms, torch, INPUT_SIZE, IN_MEAN, IN_STD
        x = torch.from_numpy(cv2.resize(img_rgb, (INPUT_SIZE, INPUT_SIZE))).permute(2, 0, 1)
        x = x.float().div(255.0)
        x = transforms.Normalize(IN_MEAN, IN_STD)(x).unsqueeze(0).to(device)
        with torch.no_grad():
            probs = torch.softmax(model(x), dim=1)[0]
        grade = int(probs.argmax())

        expl = compute_explain(img_rgb, model, device, gcam, grade,
                               explain_referable=True)

        gc, rc = expl["gradeCam"], expl["referableCam"]
        att, ev = expl["attentionImage"], expl["evidenceOverlay"]
        assert expl["note"] == "Model attention - not proof of causality"

        if gc is not None:
            stats["gradeCamNonEmpty"] += bool(gc.max() > 1e-6)
            stats["gradeCamSized"] += (gc.shape == (H, W))
        if rc is not None:
            stats["referableCamNonEmpty"] += bool(rc.max() > 1e-6)
            stats["referableCamSized"] += (rc.shape == (H, W))
        if att is not None:
            stats["overlaySized"] += (att.shape == (H, W, 3) and att.dtype == np.uint8)
        assert ev.shape == (H, W, 3) and ev.dtype == np.uint8, "evidenceOverlay HxWx3 uint8"

        # separate artifact outputs: original | raw heatmap | overlay
        base = row["image"].replace("/", "__").replace(".png", "")
        save_artifact(artifacts_root, f"{i:02d}_{base}_original.png", img_rgb)
        if gc is not None:
            save_artifact(artifacts_root, f"{i:02d}_{base}_heatmap_grade.npy", gc)
        if att is not None:
            save_artifact(artifacts_root, f"{i:02d}_{base}_overlay.png", att)

        processed.append({
            "image": row["image"], "gtGrade": int(row["grade"]),
            "predGrade": grade, "heatmap": gc is not None,
            "overlay": att is not None,
        })
        print(f"  [{i}] gt={row['grade']} pred={grade} HxW={H}x{W} "
              f"gradeCam_max={0.0 if gc is None else float(gc.max()):.3f} "
              f"referableCam_max={0.0 if rc is None else float(rc.max()):.3f}")

    manifest = {
        "model": MODEL,
        "device": device,
        "n": n_total,
        "split": "validation-only (APTOS)",
        "checks": stats,
        "samples": processed,
        "artifactsDir": artifacts_root,
        "note": "Model attention - not proof of causality",
    }
    with open(os.path.join(artifacts_root, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)

    assert stats["gradeCamNonEmpty"] == n_total and stats["gradeCamSized"] == n_total, stats
    assert stats["referableCamNonEmpty"] == n_total and stats["referableCamSized"] == n_total, stats
    assert stats["overlaySized"] == n_total, stats

    print("\n--- Grad-CAM smoke test PASSED ---")
    print(f"n={n_total} validation-only sample; model={MODEL}; split=APTOS val (no test/Messidor2)")
    print(json.dumps(stats))
    print(f"artifacts -> {os.path.abspath(artifacts_root)}")
    print("note: attention only; NOT causal proof; lesion evidence NOT fabricated.")


if __name__ == "__main__":
    main()