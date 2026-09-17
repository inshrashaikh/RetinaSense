"""
RetinaSense — real-path regression check (no MATLAB required).

Verifies that the REAL trained screening artifact set is consumed end-to-end
exactly as scripts/runPipeline.m does in default (non-mock) mode:

    load_model(resnet50_dr_aptos.pt)
    -> T from resnet50_calib.mat (scipy)
    -> run_pipeline_case() on REAL APTOS images (manifest: data/manifests/folds.csv)
    -> grade 0..4 + referable (grade >= 2) + temperature-scaled calibration
       + confidence / uncertainty / reviewRequired  (docs/ARCHITECTURE.md �4)

Mirrored config semantics (config/experiment_config.m -> loadModelRecord):
    model.available == True when backbone_benchmark.json records a chosen
    backbone — decoupled from targetsMet (the honest, non-gating outcome).

Run (from repo root, real artifacts + data already present):
    python tools/python_verifier/real_path_check.py

Exits 1 if any contract check fails or if the real artifacts are missing.
This is a verification tool, not a metric claim: it never fabricates numbers
(AGENTS.md guardrail #1).
"""

import json
import os
import sys

import cv2
import numpy as np
import pandas as pd
import scipy.io
import torch

from experiment_pipeline import (
    DATA_ROOT,
    MANIFEST,
    MODELS_DIR,
    REFER_THRESHOLD,
    GradCAM,
    apply_calibration,
    grad_cam_layer,
    load_model,
    run_pipeline_case,
)

BACKBONE = "resnet50"


def _fail(fails, name, msg=""):
    line = f"FAIL: {name}" + (f"  ({msg})" if msg else "")
    print(line)
    fails.append(line)


def run_checks():
    fails = []
    rec_file = os.path.join(MODELS_DIR, "backbone_benchmark.json")
    pt_file = os.path.join(MODELS_DIR, f"{BACKBONE}_dr_aptos.pt")
    cal_file = os.path.join(MODELS_DIR, f"{BACKBONE}_calib.mat")

    def ok(cond, name, msg=""):
        if cond:
            print(f"ok   {name}")
        else:
            _fail(fails, name, msg)
        return cond

    # ---- 1) Model availability semantics (config/experiment_config.m mirror) ----
    if not os.path.exists(rec_file):
        _fail(fails, "benchmark record present",
              "data/models/backbone_benchmark.json missing")
    else:
        with open(rec_file, encoding="utf-8") as fh:
            rec = json.load(fh)
        chosen = rec.get("chosenBackbone") or ""
        ok(bool(chosen), "record selects a backbone (model.available)",
           f"chosenBackbone={chosen!r}")
        if rec.get("targetsMet"):
            print("warn record claims targetsMet=true (review before trusting!)")
        else:
            print("note targetsMet=false is recorded honestly (non-gating)")

    # ---- 2) Real calibration artifact (T) ----
    if not os.path.exists(cal_file):
        _fail(fails, "calibration artifact present", f"{cal_file} missing")
    else:
        try:
            d = scipy.io.loadmat(cal_file)
            T = float(np.asarray(d["T"]).squeeze())
            ok(T > 0 and np.isfinite(T), "T is a positive finite scalar", f"T={T}")
        except Exception as exc:
            _fail(fails, "calibration artifact readable", str(exc))
            T = None
        if isinstance(T, float):
            print(f"note calibration T = {T:.6f}")

    # ---- 3) Real model artifact loads ----
    if not os.path.exists(pt_file):
        _fail(fails, "real model artifact present", f"{pt_file} missing")
        return fails
    try:
        model = load_model(BACKBONE)  # full state_dict round-trip -> no fake model
    except Exception as exc:
        _fail(fails, "real model loads from state_dict", str(exc))
        return fails
    model.eval()
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)
    print(f"note loaded {BACKBONE} ({sum(p.numel() for p in model.parameters())/1e6:.1f}M params) on {device}")

    # ---- 4) Real images through the full pipeline ----
    df = pd.read_csv(MANIFEST)
    test = df[df["split"] == "test"]
    if len(test) == 0:
        _fail(fails, "manifest has a test split")
        return fails
    picks = []
    for g in sorted(test["grade"].unique()):
        picks.extend(test[test["grade"] == g]["image"].head(2).tolist())
    picks = picks[:10]
    print(f"note running real pipeline over {len(picks)} APTOS test images")

    for img_rel in picks:
        path = os.path.join(DATA_ROOT, img_rel)
        if not os.path.exists(path):
            _fail(fails, f"image present: {img_rel}")
            continue
        res = run_pipeline_case(path, model, device, BACKBONE, gcam=None,
                                calibration_t=T if isinstance(T, float) else 1.0)
        qclass = res["quality"]["class"]
        ok(qclass in ("good", "borderline", "ungradable"), f"{img_rel}: quality class", qclass)

        if "exit" in res:
            ok(res["exit"] in ("qualityGate", "enhancementRecheck"),
               f"{img_rel}: honest gate exit", res["exit"])
            ok("grade" not in res, f"{img_rel}: nothing graded after gate exit")
            continue

        grade = res["grade"]
        ok(isinstance(grade, int) and 0 <= grade <= 4, f"{img_rel}: grade 0..4", str(grade))
        referable = res["referable"]
        ok(isinstance(referable, bool) and referable == (grade >= REFER_THRESHOLD),
           f"{img_rel}: referable == grade>=2", f"referable={referable} grade={grade}")
        ok(0.0 <= res["referableProb"] <= 1.0, f"{img_rel}: referableProb in [0,1]")
        probs = res["probs"]
        ok(len(probs) == 5 and abs(sum(probs) - 1.0) < 1e-6,
           f"{img_rel}: rawProbs 1x5 sum 1", f"sum={sum(probs):.6f}")

        cal = res["calibrated"]
        ok(len(cal["calibratedProbs"]) == 5 and
           abs(sum(cal["calibratedProbs"]) - 1.0) < 1e-6,
           f"{img_rel}: calibratedProbs sum 1",
           f"sum={sum(cal['calibratedProbs']):.6f}")
        ok(0.0 <= cal["confidence"] <= 1.0, f"{img_rel}: confidence in [0,1]",
           f"{cal['confidence']:.4f}")
        ok(0.0 <= cal["uncertainty"] <= 1.0, f"{img_rel}: uncertainty in [0,1]",
           f"{cal['uncertainty']:.4f}")
        ok(isinstance(cal["reviewRequired"], bool), f"{img_rel}: reviewRequired is bool")
        print(f"note {img_rel}: grade={grade} referable={referable} "
              f"conf={cal['confidence']:.3f} unc={cal['uncertainty']:.3f} "
              f"review={cal['reviewRequired']}")

    # ---- 5) Explainability still works on the real net (one pass) ----
    img_rel = picks[0]
    path = os.path.join(DATA_ROOT, img_rel)
    gcam = GradCAM(model, grad_cam_layer(model, BACKBONE))
    res = run_pipeline_case(path, model, device, BACKBONE, gcam=gcam,
                            calibration_t=T if isinstance(T, float) else 1.0)
    if "exit" not in res:
        cam = res["explain"]["gradCam"]
        H, W = cv2.imread(path).shape[:2]
        ok(cam is not None and len(cam) == H and len(cam[0]) == W,
           "gradCam map matches input HxW", f"cam={None if cam is None else (len(cam), len(cam[0]))} vs {H}x{W}")
        ok(res["explain"]["attentionImage"] is not None, "attention overlay produced")
        ok(res["explain"]["note"], "explainability safety note present")

    return fails


def main():
    print("=" * 64)
    print("RetinaSense real-path check (real resnet50 + T + APTOS on CPU)")
    print("=" * 64)
    fails = run_checks()
    print("-" * 64)
    if fails:
        print(f"RESULT: {len(fails)} check(s) FAILED (exit 1)")
        return 1
    print("RESULT: all real-path checks passed (grade/referable/calibration/explain)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())