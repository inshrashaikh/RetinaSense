"""
RetinaSense — real end-to-end AI/ML experiment pipeline (PyTorch mirror).

THIS IS THE LIVE, HONEST RUNNER for Member 1's AI/ML workstream. It mirrors
the MATLAB contracts (docs/ARCHITECTURE.md §4) and the module layout
(preprocessing/, classification/, calibration/, explainability/, evaluation/)
in executable PyTorch, and REPORT ONLY REAL NUMBERS. It never fabricates
metrics (AGENTS.md guardrail #1).

Pipeline exercised:
    Fundus image
      -> image quality gate (classical CV, mirrors preprocessing/assessQuality.m)
      -> good/borderline/ungradable + recapture guidance
      -> enhancement for borderline (CLAHE + illum-norm + denoise, mirrors enhanceImage.m)
      -> DR CNN (ResNet-50 vs EfficientNet-B0 fine-tuned on APTOS 2019)
      -> grade 0..4 + referable (>=2)
      -> calibrated confidence + normalized-entropy uncertainty
      -> Grad-CAM attention
      -> metrics: confusion, SE/SP referable, AUROC, kappa, ECE

Backbone selection is benchmark-driven (§3.2): the harness trains BOTH
candidates, reports the four-axis table, and records the chosen backbone +
metrics into data/models/backbone_benchmark.json — the same file
config/experiment_config.m loads (cfg.model).

Run (from repo root):
    python tools/python_verifier/experiment_pipeline.py [--max-epochs N]
        [--backbones resnet50,efficientnetb0] [--data-root data/raw/aptos/images]
        [--manifest data/manifests/folds.csv]

Dependencies: torch, torchvision, numpy, PIL, pandas, cv2, scipy, sklearn.
"""

import argparse
import io
import json
import os
import sys
import time
from collections import Counter

import numpy as np

import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader, Subset
from torchvision import models, transforms

try:
    import cv2
except ImportError:  # pragma: no cover
    cv2 = None

import pandas as pd
from PIL import Image
from scipy.optimize import minimize_scalar
from sklearn.metrics import cohen_kappa_score, confusion_matrix, roc_auc_score

# ---------------------------------------------------------------------------
# Config mirror (config/experiment_config.m + sub-configs)
# ---------------------------------------------------------------------------
SEED = 42
REFER_THRESHOLD = 2           # referable DR = grade >= 2 (Level 2+)

QUALITY = {
    "metricLow": {"focus": 0.25, "illumination": 0.20, "fovCoverage": 0.30, "artifacts": 0.30},
    "metricMid": {"focus": 0.55, "illumination": 0.50, "fovCoverage": 0.55, "artifacts": 0.50},
    "weights": {"focus": 0.40, "illumination": 0.25, "fovCoverage": 0.20, "artifacts": 0.15},
    "goodScore": 0.65,
    "borderlineScore": 0.40,
}

CALIBRATION = {"confidenceLow": 0.80, "uncertaintyHigh": 0.30, "temperatureMode": "fit",
               "normEntropyMode": "log5"}

BENCHMARK = {"se": 0.90, "sp": 0.85, "tieBreak": "size"}   # SIH targets (decision rules)

TRAIN = {
    "backboneCandidates": ["resnet50", "efficientnetb0"],
    "imagenetPretrained": True,
    "miniBatchSize": 16,
    "maxEpochs": 3,
    "initialLearnRate": 1e-4,
    "augmentation": True,
    "classWeights": "inverseFrequency",
    "focalGamma": 2.0,
}

INPUT_SIZE = 224

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_ROOT = os.path.join(REPO_ROOT, "data", "raw", "aptos", "images")
MANIFEST = os.path.join(REPO_ROOT, "data", "manifests", "folds.csv")
MODELS_DIR = os.path.join(REPO_ROOT, "data", "models")
OUTPUT_DIR = os.path.join(REPO_ROOT, "output")

# ImageNet normalization for torchvision pretrained weights.
IN_MEAN = [0.485, 0.456, 0.406]
IN_STD = [0.229, 0.224, 0.225]


# ---------------------------------------------------------------------------
# Seed helpers
# ---------------------------------------------------------------------------
def set_seed(seed: int = SEED):
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


# ---------------------------------------------------------------------------
# Simple logger mirroring core/logMessage.m
# ---------------------------------------------------------------------------
def log(level, stage, msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] [{level.upper()}] [{stage}] {msg}", flush=True)


# ---------------------------------------------------------------------------
# Image quality gate (mirror of preprocessing/assessQuality.m)
# In real use we feed the actual pixels; classical CV, deterministic.
# ---------------------------------------------------------------------------
def assess_quality(img_rgb):
    """img_rgb: uint8 HxWx3. Returns dict mirroring quality struct (§4.1)."""
    gray = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2GRAY).astype(np.float64) / 255.0

    # focus: variance of 3x3 Laplacian (green channel, per architecture)
    lap = cv2.Laplacian(np.clip(gray * 255, 0, 255).astype(np.uint8), cv2.CV_64F, ksize=1)
    var = lap.var()
    focus = min(1.0, var / 0.02)

    lum_mean = gray.mean()
    illum = max(0.0, min(1.0, 1.0 - abs(lum_mean - 0.5) / 0.5))

    fov_coverage = (gray > 0.06).mean()

    sat_frac = (gray > 0.985).mean()
    dark_frac = (gray < 0.01).mean()
    artifacts = max(0.0, 1.0 - (sat_frac + dark_frac))

    metrics = {"focus": float(focus), "illumination": float(illum),
               "fovCoverage": float(fov_coverage), "artifacts": float(artifacts)}
    score = sum(QUALITY["weights"][k] * metrics[k] for k in metrics)

    low_fail = [k for k in metrics if metrics[k] < QUALITY["metricLow"][k]]
    mid_fail = [k for k in metrics if metrics[k] < QUALITY["metricMid"][k]]

    if low_fail:
        klass, reasons = "ungradable", low_fail
    elif mid_fail or score < QUALITY["goodScore"]:
        klass, reasons = "borderline", mid_fail if mid_fail else ["composite"]
    else:
        klass, reasons = "good", []

    recapture = recapture_feedback(reasons) if klass == "ungradable" else {"reasonCode": "", "instruction": ""}
    return {"score": float(score), "class": klass, "metrics": metrics,
            "failureReasons": reasons, "recapture": recapture}


def recapture_feedback(reasons):
    guide = {
        "focus": ("REFOCUS", "Image is out of focus. Ask patient to hold still and refocus on the optic disc."),
        "illumination": ("FIX_LIGHTING", "Adjust illumination: avoid under/over exposure, center the light beam."),
        "fovCoverage": ("RECENTER_FOV", "Optic disc not fully visible. Recenter the field of view on the macula-disc axis."),
        "artifacts": ("CLEAR_ARTIFACTS", "Glare/saturation/clipping detected. Reduce flash intensity and ask patient to blink."),
    }
    precedence = ["focus", "illumination", "fovCoverage", "artifacts"]
    key = next((k for k in precedence if k in reasons), reasons[0] if reasons else "")
    if not key:
        return {"reasonCode": "", "instruction": ""}
    code, text = guide[key] if key in guide else ("RETAKE", "Please retake the fundus photo.")
    return {"reasonCode": code, "instruction": text}


def enhance_borderline(img_rgb):
    """Mirror of preprocessing/enhanceImage.m on a borderline image:
    CLAHE (value channel) + gamma illumination norm + mild denoise."""
    if cv2 is None:
        return img_rgb, []
    ops = []
    lab = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    l = clahe.apply(l)
    lab = cv2.merge((l, a, b))
    img = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
    ops.append("clahe")

    img = np.power(img.astype(np.float64) / 255.0, 0.85) * 255.0
    img = np.clip(img, 0, 255).astype(np.uint8)
    ops.append("illumNorm")

    img = cv2.GaussianBlur(img, (3, 3), 1.0)
    ops.append("denoise")
    return img, ops


# ---------------------------------------------------------------------------
# Dataset (mirror of prepareClassifierData.m + augmentation in trainClassifier.m)
# ---------------------------------------------------------------------------
class FundusDataset(Dataset):
    def __init__(self, rows, img_root, split, input_size=INPUT_SIZE, augment=False):
        self.rows = rows
        self.img_root = img_root
        self.augment = augment
        self.input_size = input_size
        tf_common = [transforms.Resize((input_size, input_size))]
        if augment:
            tf_common = [transforms.Resize((int(input_size * 1.1), int(input_size * 1.1))),
                         transforms.RandomHorizontalFlip(p=0.5),
                         transforms.RandomVerticalFlip(p=0.5),
                         transforms.RandomRotation(10),
                         transforms.RandomResizedCrop(input_size, scale=(0.85, 1.0))]
        self.transform = transforms.Compose(tf_common + [
            transforms.ToTensor(),
            transforms.Normalize(IN_MEAN, IN_STD),
        ])

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        r = self.rows.iloc[i]
        path = os.path.join(self.img_root, r["image"])
        img = Image.open(path).convert("RGB")
        x = self.transform(img)
        return x, int(r["grade"])


def load_splits(manifest_path=MANIFEST, data_root=DATA_ROOT, seed=SEED):
    df = pd.read_csv(manifest_path)
    # enforce Messidor-2 external-only rule
    ext = df[df["source"] == "messidor2"]
    assert (ext["split"] == "external").all(), "Messidor-2 leak into non-external split!"
    train = df[df["split"] == "train"].reset_index(drop=True)
    val = df[df["split"] == "val"].reset_index(drop=True)
    test = df[df["split"] == "test"].reset_index(drop=True)
    return train, val, test, data_root


def make_loaders(train_df, val_df, test_df, img_root, batch_size, workers=0):
    ds_tr = FundusDataset(train_df, img_root, "train", augment=TRAIN["augmentation"])
    ds_va = FundusDataset(val_df, img_root, "val", augment=False)
    ds_te = FundusDataset(test_df, img_root, "test", augment=False)
    dl_tr = DataLoader(ds_tr, batch_size=batch_size, shuffle=True, num_workers=workers)
    dl_va = DataLoader(ds_va, batch_size=batch_size, shuffle=False, num_workers=workers)
    dl_te = DataLoader(ds_te, batch_size=batch_size, shuffle=False, num_workers=workers)
    return dl_tr, dl_va, dl_te


def class_weights(train_df, num_classes=5):
    """Inverse-frequency class weights (mirror of MATLAB 'inverseFrequency')."""
    c = Counter(train_df["grade"].tolist())
    w = np.array([1.0 / max(1, c.get(g, 0)) for g in range(num_classes)])
    inv = w / w.sum() * num_classes  # mean weight = 1
    return torch.tensor(inv, dtype=torch.float32)


# ---------------------------------------------------------------------------
# Models (classification/trainClassifier.m + backbone selection §3.2)
# ---------------------------------------------------------------------------
def build_model(backbone, num_classes=5, pretrained=True):
    if backbone == "resnet50":
        m = models.resnet50(weights=models.ResNet50_Weights.IMAGENET1K_V1 if pretrained else None)
        m.fc = nn.Linear(m.fc.in_features, num_classes)
    elif backbone == "efficientnetb0":
        m = models.efficientnet_b0(
            weights=models.EfficientNet_B0_Weights.IMAGENET1K_V1 if pretrained else None)
        m.classifier[1] = nn.Linear(m.classifier[1].in_features, num_classes)
    else:
        raise ValueError(f"Unknown backbone {backbone}")
    return m


def grad_cam_layer(model, backbone):
    """Target conv layer for Grad-CAM (mirrors cfg.explainability.layers)."""
    if backbone == "resnet50":
        return model.layer4
    return model.features


class AverageMeter:
    def __init__(self): self.sum, self.n = 0.0, 0
    def update(self, v, n=1): self.sum += v * n; self.n += n
    @property
    def avg(self): return self.sum / max(1, self.n)


def train_one_epoch(model, loader, criterion, optimizer, device, max_epochs=1, epoch=1, backbone="",
                    log_every=None):
    model.train()
    am = AverageMeter()
    n_batches = max(1, len(loader))
    if log_every is None:
        log_every = max(1, n_batches // 10)  # ~10 checkpoints per epoch
    t_start = time.time()
    for i, (x, y) in enumerate(loader):
        x, y = x.to(device), y.to(device)
        optimizer.zero_grad()
        out = model(x)
        loss = criterion(out, y)
        loss.backward()
        optimizer.step()
        am.update(loss.item(), x.size(0))
        if (i + 1) % log_every == 0 or (i + 1) == n_batches:
            elapsed = time.time() - t_start
            rate = (i + 1) / max(1, elapsed)
            log("debug", "trainClassifier",
                f"[{backbone}] ep {epoch}/{max_epochs} batch {i + 1}/{n_batches} "
                f"loss={am.avg:.4f} ({rate:.2f} batch/s, {elapsed:.0f}s)")
    return am.avg


@torch.no_grad()
def evaluate(model, loader, device):
    model.eval()
    all_y, all_probs = [], []
    for x, y in loader:
        x = x.to(device)
        out = model(x)
        p = F.softmax(out, dim=1)
        all_y.append(y.numpy())
        all_probs.append(p.cpu().numpy())
    labels = np.concatenate(all_y)
    probs = np.concatenate(all_probs)
    preds = probs.argmax(axis=1)
    return labels, preds, probs


# ---------------------------------------------------------------------------
# Metrics (mirror of evaluation/metrics.m + per-class + referable)
# ---------------------------------------------------------------------------
def metrics(labels, preds, probs, conf_threshold=REFER_THRESHOLD, num_classes=5):
    labels = np.asarray(labels); preds = np.asarray(preds); probs = np.asarray(probs)
    n = len(labels)
    cm = confusion_matrix(labels, preds, labels=list(range(num_classes)))

    per_se, per_sp = [], []
    for g in range(num_classes):
        tp = np.sum((preds == g) & (labels == g))
        fn = np.sum((preds != g) & (labels == g))
        tn = np.sum((preds != g) & (labels != g))
        fp = np.sum((preds == g) & (labels != g))
        per_se.append(tp / max(1, tp + fn))
        per_sp.append(tn / max(1, tn + fp))

    ref_lab = labels >= conf_threshold
    ref_pred = preds >= conf_threshold
    tp = np.sum(ref_pred & ref_lab); fn2 = np.sum(~ref_pred & ref_lab)
    tn2 = np.sum(~ref_pred & ~ref_lab); fp2 = np.sum(ref_pred & ~ref_lab)

    ref_prob = probs[:, conf_threshold:].sum(axis=1)
    try:
        auc_ref = roc_auc_score(ref_lab, ref_prob) if len(np.unique(ref_lab)) > 1 else float("nan")
    except ValueError:
        auc_ref = float("nan")

    ece = expected_calibration_error(probs, labels)
    kappa = float(cohen_kappa_score(labels, preds, weights="quadratic"))

    return {
        "n": int(n),
        "confusion": cm.tolist(),
        "accuracy": float(np.mean(preds == labels)),
        "perClassSensitivity": per_se,
        "perClassSpecificity": per_sp,
        "referableSensitivity": float(tp / max(1, tp + fn2)),
        "referableSpecificity": float(tn2 / max(1, tn2 + fp2)),
        "aucReferable": float(auc_ref),
        "quadraticKappa": float(kappa),
        "ece": float(ece),
    }


def expected_calibration_error(probs, labels, bins=10):
    conf = probs.max(axis=1)
    pred = probs.argmax(axis=1)
    n = len(labels)
    if n == 0:
        return 0.0
    e = 0.0
    edges = np.linspace(0, 1, bins + 1)
    for i in range(bins):
        idx = np.where((conf >= edges[i]) & (conf < edges[i + 1]))[0]
        if len(idx) == 0:
            continue
        acc = np.mean(pred[idx] == labels[idx])
        e += (len(idx) / n) * abs(acc - conf[idx].mean())
    return float(e)


# ---------------------------------------------------------------------------
# Temperature scaling (calibration/fitTemperature.m + applyCalibration.m)
# ---------------------------------------------------------------------------
def fit_temperature(logits, labels, init_t=1.0):
    """Fit T>0 minimising NLL on validation logits (single-parameter, §3.7)."""
    def nll(t):
        z = logits / t
        z = z - z.max(axis=1, keepdims=True)
        logsumexp = np.log(np.exp(z).sum(axis=1))
        return float(-np.mean(z[np.arange(len(labels)), labels] - logsumexp))
    res = minimize_scalar(nll, bounds=(1e-3, 50.0), method="bounded", options={"xatol": 1e-6})
    return float(res.x)


def apply_calibration(probs, t):
    """Temperature-scaled probabilities: calibratedProbs, confidence (max),
    uncertainty (normalized entropy), reviewRequired."""
    z = np.log(np.clip(probs, 1e-12, 1.0)) / t
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    cal = e / e.sum(axis=1, keepdims=True)
    return cal


def calibrated_report(probs, labels, t, confidence_low=0.80, uncertainty_high=0.30):
    cal = apply_calibration(probs, t)
    conf = cal.max(axis=1)
    ent = np.clip(-np.sum(cal * np.log(np.clip(cal, 1e-12, 1.0)), axis=1) / np.log(5), 0.0, 1.0)
    review = (conf < confidence_low) | (ent > uncertainty_high)
    return {
        "temperature": t,
        "eceUncalibrated": expected_calibration_error(probs, labels),
        "eceCalibrated": expected_calibration_error(cal, labels),
        "reviewRequiredFrac": float(review.mean()),
        "meanConfidence": float(conf.mean()),
        "meanUncertainty": float(ent.mean()),
    }


# ---------------------------------------------------------------------------
# Grad-CAM (explainability/computeGradCAM.m) — real attention, not causality
# ---------------------------------------------------------------------------
class GradCAM:
    def __init__(self, model, target_layer):
        self.model = model
        self.gradients = None
        self.activations = None
        h1 = target_layer.register_forward_hook(self._save_activation)
        # Modern torch (>= 1.10): prefer full_backward_hook so we get the output
        # gradient even when only the loss (not activations) requires grad.
        if hasattr(target_layer, "register_full_backward_hook"):
            h2 = target_layer.register_full_backward_hook(self._save_gradient)
        else:
            h2 = target_layer.register_backward_hook(self._save_gradient)
        self.hooks = [h1, h2]

    def _save_activation(self, module, inp, out):
        self.activations = out.detach()

    def _save_gradient(self, module, grad_in, grad_out):
        self.gradients = grad_out[0].detach()

    def __call__(self, x, class_idx):
        self.model.zero_grad()
        out = self.model(x)
        if class_idx == "referable":
            # Referable DR decision (grade >= 2): explain the log-sum-exp of the
            # referable logits, i.e. the logit mass driving P(grade>=2).
            score = torch.logsumexp(out[0, REFER_THRESHOLD:], dim=0)
        else:
            score = out[0, class_idx]
        score.backward()
        acts = self.activations[0]
        grads = self.gradients[0]
        weights = grads.mean(dim=(1, 2), keepdim=True)         # GAP of gradients
        cam = (weights * acts).sum(dim=0).clamp(min=0)         # ReLU
        cam = cam - cam.min()
        if cam.max() > 0:
            cam = cam / cam.max()
        H, W = x.shape[2], x.shape[3]
        cam = F.interpolate(cam.unsqueeze(0).unsqueeze(0), size=(H, W), mode="bilinear",
                            align_corners=False)[0, 0]
        return cam.cpu().numpy(), out.detach().cpu().numpy()


# ---------------------------------------------------------------------------
# Explainability contract (§4.5) — computeGradCAM.m mirror
# ---------------------------------------------------------------------------
def overlay_cam(image_rgb, cam):
    """Blend a jet colormapped Grad-CAM heatmap over the grayscale original.

    Mirrors computeGradCAM.m: `attentionImage` HxWx3 uint8, 0.55*base + 0.45*heat.
    """
    h, w = cam.shape[:2]
    base = cv2.cvtColor(cv2.resize(image_rgb, (w, h)), cv2.COLOR_RGB2GRAY)
    base = cv2.cvtColor(base, cv2.COLOR_GRAY2RGB).astype(np.float64) / 255.0

    cam01 = np.clip(cam, 0.0, 1.0)
    heat = cv2.applyColorMap((cam01 * 255).astype(np.uint8), cv2.COLORMAP_JET)
    heat = cv2.cvtColor(heat, cv2.COLOR_BGR2RGB).astype(np.float64) / 255.0

    blended = (0.55 * base + 0.45 * heat) * 255.0
    return np.clip(blended, 0, 255).astype(np.uint8)


def compute_explain(working_rgb, model, device, gcam, grade, explain_referable=True):
    """Full §4.5 explainability contract (mirror of computeGradCAM.m).

    working_rgb : the RGB image the classifier actually saw (post-enhancement).
    Returns dict with:
      gradeCam/referableCam   HxW double attention maps (0..1) or None
      gradCam                 HxW double (priority: gradeCam, else referableCam)
      attentionImage          HxWx3 uint8 jet overlay (or None if no cam)
      evidenceOverlay         HxWx3 uint8; empty evidence -> plain (honest empty)
      note                    'Model attention - not proof of causality'
    Lesion evidence is NOT used here (guardrail: no fabricated clinical findings).
    """
    H, W = working_rgb.shape[:2]
    x = torch.from_numpy(cv2.resize(working_rgb, (INPUT_SIZE, INPUT_SIZE))).permute(2, 0, 1)
    x = x.float().div(255.0)
    x = transforms.Normalize(IN_MEAN, IN_STD)(x).unsqueeze(0).to(device)

    grade_cam = None
    referable_cam = None
    if grade is not None and 0 <= grade < 5:
        grade_cam, _ = gcam(x, grade)                 # explain predicted DR class
    if explain_referable:
        referable_cam, _ = gcam(x, "referable")       # explain P(grade>=2) decision

    def _to_size(cam):
        if cam is None:
            return None
        if cam.shape != (H, W):
            cam = cv2.resize(cam, (W, H))
        return np.asarray(cam, dtype=np.float64)

    grade_cam = _to_size(grade_cam)
    referable_cam = _to_size(referable_cam)
    use_cam = grade_cam if grade_cam is not None else referable_cam

    attention = overlay_cam(working_rgb, use_cam) if use_cam is not None else None

    # Evidence overlay: honest empty when no validated lesion evidence (§3.6).
    evidence_overlay = np.ascontiguousarray(
        cv2.cvtColor(cv2.cvtColor(working_rgb, cv2.COLOR_RGB2GRAY), cv2.COLOR_GRAY2RGB))

    return {
        "gradeCam": grade_cam,
        "referableCam": referable_cam,
        "gradCam": use_cam,
        "attentionImage": attention,
        "evidenceOverlay": evidence_overlay,
        "note": "Model attention - not proof of causality",
    }


# ---------------------------------------------------------------------------
# Benchmark harness (scripts/benchmark_backbones.m)
# ---------------------------------------------------------------------------
def save_benchmark_record(record):
    os.makedirs(MODELS_DIR, exist_ok=True)
    rec_file = os.path.join(MODELS_DIR, "backbone_benchmark.json")
    with open(rec_file, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, default=str)
    log("info", "benchmark_backbones", f"Recorded -> {rec_file}")
    return rec_file


def benchmark(backbones, dl_tr, dl_va, dl_te, train_df, max_epochs, device):
    per_backbone = {}
    criterion_w = class_weights(train_df).to(device)
    for bb in backbones:
        log("info", "benchmark_backbones", f"Backbone: {bb}")
        set_seed(SEED)
        t_load = time.time()
        log("info", "benchmark_backbones", f"[{bb}] initializing model + loading weights...")
        model = build_model(bb).to(device)
        n_params = sum(p.numel() for p in model.parameters())
        log("info", "benchmark_backbones",
            f"[{bb}] model ready ({time.time() - t_load:.1f}s, {n_params/1e6:.1f}M params)")
        criterion = nn.CrossEntropyLoss(weight=criterion_w)
        optimizer = torch.optim.SGD(model.parameters(), lr=TRAIN["initialLearnRate"],
                                    momentum=0.9, weight_decay=1e-4)

        t0 = time.time()
        for ep in range(1, max_epochs + 1):
            t_ep = time.time()
            log("info", "trainClassifier",
                f"[{bb}] epoch {ep}/{max_epochs} starting (train={len(dl_tr.dataset)} imgs, "
                f"batch={TRAIN['miniBatchSize']})")
            loss = train_one_epoch(model, dl_tr, criterion, optimizer, device,
                                   max_epochs=max_epochs, epoch=ep, backbone=bb)
            log("info", "trainClassifier",
                f"[{bb}] epoch {ep}/{max_epochs} DONE loss={loss:.3f} "
                f"({time.time() - t_ep:.0f}s)")
        train_sec = time.time() - t0

        # Latency: mean predict() time over the val loader.
        model.eval()
        log("info", "evaluateClassifier", f"[{bb}] measuring predict latency on val set...")
        t0 = time.time()
        with torch.no_grad():
            for x, _ in dl_va:
                model(x.to(device))
        lat_ms = (time.time() - t0) / max(1, len(dl_va.dataset)) * 1e3

        log("info", "evaluateClassifier", f"[{bb}] evaluating on held-out test set...")
        labels, preds, probs = evaluate(model, dl_te, device)
        m = metrics(labels, preds, probs)
        save_model(model, bb)                    # persist the trained artifact (§8)
        size_bytes = model_size_bytes(bb)
        meets = m["referableSensitivity"] >= BENCHMARK["se"] and m["referableSpecificity"] >= BENCHMARK["sp"]
        per_backbone[bb] = dict(m,
                                sizeBytes=size_bytes,
                                trainSeconds=round(train_sec, 1),
                                latencyMs=round(lat_ms, 2),
                                meetsTargets=bool(meets))
        log("info", "benchmark_backbones",
            f"[{bb}] test SE={100*m['referableSensitivity']:.1f} SP={100*m['referableSpecificity']:.1f} "
            f"AUROC={m['aucReferable']:.3f} acc={100*m['accuracy']:.1f} "
            f"lat={lat_ms:.1f}ms size={size_bytes/1e6:.1f}MB meets={meets}")

    # ---- Selection rule (§3.2, mirrors benchmark_backbones.m) ----
    meeting = [bb for bb in backbones if per_backbone[bb]["meetsTargets"]]
    if meeting:
        best = min(meeting, key=lambda bb: per_backbone[bb]["sizeBytes"])  # tie-break: size
        targets_met = True
    else:
        best = max(backbones, key=lambda bb: per_backbone[bb]["aucReferable"])
        targets_met = False
    log("info", "benchmark_backbones", f"Chosen: {best} (targetsMet={targets_met})")

    return per_backbone, best, targets_met


def model_size_bytes(bb):
    path = os.path.join(MODELS_DIR, f"{bb}_dr_aptos.pt")
    return os.path.getsize(path) if os.path.exists(path) else 0


def save_model(model, bb):
    os.makedirs(MODELS_DIR, exist_ok=True)
    p = os.path.join(MODELS_DIR, f"{bb}_dr_aptos.pt")
    torch.save(model.state_dict(), p)
    return p


def load_model(bb):
    model = build_model(bb)
    p = os.path.join(MODELS_DIR, f"{bb}_dr_aptos.pt")
    model.load_state_dict(torch.load(p, map_location="cpu", weights_only=True))
    return model


# ---------------------------------------------------------------------------
# Full pipeline on one real image (mirrors scripts/runPipeline.m §1 end-to-end)
# ---------------------------------------------------------------------------
def run_pipeline_case(img_path, model, device, bb, gcam=None, calibration_t=1.0):
    img_rgb = cv2.cvtColor(cv2.imread(img_path), cv2.COLOR_BGR2RGB)
    quality = assess_quality(img_rgb)
    applied = []
    working = img_rgb
    if quality["class"] == "borderline":
        working, applied = enhance_borderline(img_rgb)
        quality2 = assess_quality(working)
        if quality2["class"] == "ungradable":
            return {"quality": quality2, "recapture": quality2["recapture"],
                    "exit": "enhancementRecheck", "note": "Enhanced image still ungradable"}
        quality = quality2
        quality["enhanced"] = True
        quality["appliedOps"] = applied
    if quality["class"] == "ungradable":
        return {"quality": quality, "recapture": quality["recapture"], "exit": "qualityGate"}

    x = torch.from_numpy(cv2.resize(working, (INPUT_SIZE, INPUT_SIZE))).permute(2, 0, 1).float().div(255.0)
    x = transforms.Normalize(IN_MEAN, IN_STD)(x).unsqueeze(0).to(device)
    with torch.no_grad():
        out = model(x)
        probs = F.softmax(out, dim=1)[0].cpu().numpy()
    grade = int(probs.argmax())
    referable_prob = float(probs[REFER_THRESHOLD:].sum())
    referable = grade >= REFER_THRESHOLD

    cal_probs = apply_calibration(probs[None, :], calibration_t)[0]
    cal_conf = float(cal_probs.max())
    cal_unc = float(np.clip(-np.sum(cal_probs * np.log(np.clip(cal_probs, 1e-12, 1)))/np.log(5), 0.0, 1.0))
    cal_single = {
        "calibratedProbs": cal_probs.tolist(),
        "temperature": calibration_t,
        "confidence": cal_conf,
        "uncertainty": cal_unc,
        "reviewRequired": bool(cal_conf < CALIBRATION["confidenceLow"] or
                               cal_unc > CALIBRATION["uncertaintyHigh"]),
    }
    gcam_map = None
    explain = {"gradeCam": None, "referableCam": None, "gradCam": None,
               "attentionImage": None, "evidenceOverlay": None,
               "note": "Model attention - not proof of causality"}
    if gcam is not None:
        explain = compute_explain(working, model, device, gcam, grade,
                                  explain_referable=True)
        gcam_map = explain["gradCam"]
    return {"quality": quality, "grade": grade, "referable": referable,
            "referableProb": referable_prob, "probs": probs.tolist(),
            "calibrated": cal_single,
            "gradCam": gcam_map.tolist() if gcam_map is not None else None,
            "explain": {
                "gradCam": explain["gradCam"].tolist() if explain["gradCam"] is not None else None,
                "attentionImage": explain["attentionImage"].tolist() if explain["attentionImage"] is not None else None,
                "evidenceOverlay": explain["evidenceOverlay"].tolist() if explain["evidenceOverlay"] is not None else None,
                "gradeCam": explain["gradeCam"].tolist() if explain["gradeCam"] is not None else None,
                "referableCam": explain["referableCam"].tolist() if explain["referableCam"] is not None else None,
                "note": explain["note"]},
            "note": "Model attention - not proof of causality"}


# ---------------------------------------------------------------------------
# Main experiment driver
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-epochs", type=int, default=TRAIN["maxEpochs"])
    ap.add_argument("--backbones", default=",".join(TRAIN["backboneCandidates"]))
    ap.add_argument("--data-root", default=DATA_ROOT)
    ap.add_argument("--manifest", default=MANIFEST)
    ap.add_argument("--batch-size", type=int, default=TRAIN["miniBatchSize"])
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--limit", type=int, default=0,
                    help="subsample TRAINING to this many images (smoke test; 0 = full)")
    args = ap.parse_args()

    TRAIN["maxEpochs"] = args.max_epochs
    TRAIN["miniBatchSize"] = args.batch_size
    backbones = [b.strip() for b in args.backbones.split(",") if b.strip()]

    set_seed(SEED)
    device = torch.device(args.device if torch.cuda.is_available() else "cpu")
    log("info", "pipeline", f"device={device} backbones={backbones} epochs={TRAIN['maxEpochs']}")

    if not os.path.exists(args.manifest):
        raise SystemExit(f"Manifest not found: {args.manifest} (run data prep first)")
    if not os.path.exists(args.data_root):
        raise SystemExit(f"Data root not found: {args.data_root}")

    log("info", "prepareClassifierData", f"Loading manifest: {args.manifest}")
    train_df, val_df, test_df, img_root = load_splits(args.manifest, args.data_root)
    if args.limit > 0 and len(train_df) > args.limit:
        groups = [g for _, g in train_df.groupby("grade")]
        subsampled = pd.concat(
            [g.sample(max(1, min(len(g), int(args.limit / 5))), random_state=SEED)
             for g in groups], ignore_index=True)
        train_df = subsampled
        log("warn", "prepareClassifierData",
            f"SMOKE TEST: training subsampled to {len(train_df)} images")
    log("info", "prepareClassifierData", "Creating dataloaders (lazy; images loaded on access)...")
    dl_tr, dl_va, dl_te = make_loaders(train_df, val_df, test_df, img_root, TRAIN["miniBatchSize"])
    log("info", "prepareClassifierData",
        f"train={len(train_df)} val={len(val_df)} test={len(test_df)} "
        f"OPS={sorted(train_df.grade.unique().tolist())}")

    # 1) Benchmark backbones
    log("info", "pipeline", "Stage 1/4: backbone benchmark (train both candidates)")
    t_stage = time.time()
    per_backbone, best, targets_met = benchmark(backbones, dl_tr, dl_va, dl_te, train_df,
                                                args.max_epochs, device)
    log("info", "pipeline", f"Stage 1/4 complete ({time.time() - t_stage:.0f}s)")
    record = {
        "chosenBackbone": best,
        "targetsMet": targets_met,
        "perBackbone": per_backbone,
        "targets": {"se": BENCHMARK["se"], "sp": BENCHMARK["sp"]},
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "experiment": "APTOS 2019 (huggingface bumbledeep mirror, 224x224), fine-tuned on CPU",
        "n_train": int(len(train_df)), "n_val": int(len(val_df)), "n_test": int(len(test_df)),
        "epochs": args.max_epochs,
    }
    save_benchmark_record(record)

    # 2) Calibration on VALIDATION logits, then ECE on TEST (honest)
    log("info", "pipeline", "Stage 2/4: calibration (temperature on val logits -> ECE on test)")
    t_stage = time.time()
    logits_te = collect_logits(load_model(best), dl_te, device)
    labels_te = np.concatenate([y.numpy() for _, y in dl_te])
    logits_va = collect_logits(load_model(best), dl_va, device)
    labels_va = np.concatenate([y.numpy() for _, y in dl_va])
    T = fit_temperature(logits_va, labels_va)
    cal_te = calibrated_report(softmax(logits_te), labels_te, T)
    log("info", "applyCalibration", f"T={T:.3f} ECE_uncal={cal_te['eceUncalibrated']:.4f} "
        f"ECE_cal={cal_te['eceCalibrated']:.4f} reviewFrac={cal_te['reviewRequiredFrac']:.3f}")
    log("info", "pipeline", f"Stage 2/4 complete ({time.time() - t_stage:.0f}s)")

    # 3) Grad-CAM demo + full pipeline on test samples
    log("info", "pipeline", "Stage 3/4: Grad-CAM + end-to-end pipeline on test samples")
    t_stage = time.time()
    model = load_model(best).to(device).eval()
    gcam = GradCAM(model, grad_cam_layer(model, best))
    demo_cases = []
    for i in range(min(5, len(test_df))):
        row = test_df.iloc[i]
        path = os.path.join(img_root, row["image"])
        res = run_pipeline_case(path, model, device, best, gcam, calibration_t=T)
        res["image"] = row["image"]; res["trueGrade"] = int(row["grade"])
        demo_cases.append(res)
        log("info", "pipeline", f"{row['image']} true={row['grade']} -> "
            f"quality={res['quality']['class']} grade={res['grade']} referable={res['referable']}")
    log("info", "pipeline", f"Stage 3/4 complete ({time.time() - t_stage:.0f}s)")

    # 4) Write an honest experiment report
    log("info", "pipeline", "Stage 4/4: writing experiment report")
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    report = {
        "experiment": record,
        "calibration": cal_te,
        "demoCases": demo_cases,
    }
    report_file = os.path.join(OUTPUT_DIR, "experiment_report.json")
    with open(report_file, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, default=lambda o: str(o))
    print_summary(record, cal_te)
    log("info", "pipeline", f"Full report -> {report_file}")
    return report


@torch.no_grad()
def collect_logits(model, loader, device):
    model.eval()
    all_out = []
    for x, _ in loader:
        all_out.append(model(x.to(device)).cpu().numpy())
    return np.concatenate(all_out)


def softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def print_summary(record, cal_te):
    print("\n" + "=" * 78)
    print("RetinaSense AI/ML experiment — REAL results")
    print("=" * 78)
    print(f"Backbone benchmark (train={record['n_train']} val={record['n_val']} "
          f"test={record['n_test']}, epochs={record['epochs']}):")
    hdr = f"{'backbone':<16}{'SE%':>8}{'SP%':>8}{'AUROC':>8}{'acc%':>8}{'K':>7}{'ECE':>8}{'latms':>9}{'sizeMB':>9}"
    print(hdr); print("-" * 78)
    for bb, r in record["perBackbone"].items():
        print(f"{bb:<16}{100*r['referableSensitivity']:>8.1f}{100*r['referableSpecificity']:>8.1f}"
              f"{r['aucReferable']:>8.3f}{100*r['accuracy']:>8.1f}{r['quadraticKappa']:>7.3f}"
              f"{r['ece']:>8.4f}{r['latencyMs']:>9.1f}{r['sizeBytes']/1e6:>9.1f}")
    print(f"\nChosen backbone: {record['chosenBackbone']} (clinical targets met: "
          f"{record['targetsMet']})")
    print(f"Calibration: T={cal_te['temperature']:.3f}; "
          f"ECE uncal = {cal_te['eceUncalibrated']:.4f} -> cal = {cal_te['eceCalibrated']:.4f}; "
          f"review-required fraction = {100*cal_te['reviewRequiredFrac']:.1f}%")
    print("=" * 78)


if __name__ == "__main__":
    main()