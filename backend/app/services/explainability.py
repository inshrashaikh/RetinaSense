"""Real explainability service (backend mirror of §4.5 Grad-CAM).

When `EXPLAIN_ENABLED` is on and the trained benchmark model is present
(data/models/<backbone>_dr_aptos.pt), screening computes GENUINE Grad-CAM
attention on the ACTUAL uploaded fundus image using the real trained PyTorch
model — mirroring `tool_python_verifier/explainability/computeGradCAM.m`
(Grad-CAM on the grade-2 referable class, jet colormap, 0.55 base + 0.45
heat overlay, honest evidence-empty overlay).

Honesty contract:
  * Attention is model attention — never proof of causality; note returned
    verbatim ("Model attention - not proof of causality").
  * The lesion-evidence overlay is ALWAYS a plain grayscale of the original
    (honest empty) — the pipeline never invents lesions or lesion evidence.
  * If the model or torch is missing the service returns None and screening
    keeps its honest empty explainability — never a fabricated map.
"""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import numpy as np

from ..config import (
    EXPLAIN_BACKBONE,
    EXPLAIN_ENABLED,
    EXPLAIN_INPUT_SIZE,
    EXPLAIN_MEAN,
    EXPLAIN_MODEL_PATH,
    EXPLAIN_REFER_THRESHOLD,
    EXPLAIN_STD,
)

_logger = logging.getLogger(__name__)

_EXPLAIN_NOTE = "Model attention - not proof of causality"
_EXPLAIN_NUM_CLASSES = 5

_model = None
_model_tried = False


def _load_model() -> Any | None:
    """Load the trained benchmark model once (lazy singleton).

    Returns None when disabled, the model file is missing, or torch is not
    installed. The caller (screening) then keeps honest-empty explainability.
    """
    global _model, _model_tried
    if _model_tried:
        return _model
    _model_tried = True

    if not EXPLAIN_ENABLED:
        return None
    if not EXPLAIN_MODEL_PATH.is_file():
        _logger.warning(
            "explainability: model not found at %s — attention stays honest-empty",
            EXPLAIN_MODEL_PATH,
        )
        return None

    try:
        import torch
        import torch.nn as nn
        from torchvision import models

        model = models.resnet50(weights=None) if EXPLAIN_BACKBONE == "resnet50" else _build_other()
        num_ftrs = model.fc.in_features
        model.fc = nn.Linear(num_ftrs, _EXPLAIN_NUM_CLASSES)
        model.load_state_dict(
            torch.load(str(EXPLAIN_MODEL_PATH), map_location="cpu", weights_only=True)
        )
        model.eval()
        _model = model
    except Exception as exc:
        _logger.warning("explainability: model load failed (%s) — attention stays honest-empty", exc)
        _model = None
    return _model


def _build_other():
    # No other backbone is trained/shipped in this prototype.
    return None


# ─── Grad-CAM (mirror of tools/python_verifier/explainability/gradcam.py) ──

def _anchor_layer(model: Any) -> Any:
    """Target layer for attention. resnet50 -> layer4 (resnet.layer4)."""
    if hasattr(model, "layer4"):
        return model.layer4
    return model.features


class _GradCAM:
    """Gradient-weighted attention for the referable (grade>=2) decision class.

    Miami §4.5: attention explains the referable decision; attention is NOT
    causality. Implements the same module hooks as gradcam.py.
    """

    def __init__(self, model: Any, target_layer: Any) -> None:
        self.model = model
        self.activations: dict[str, Any] = {}
        self.gradients: dict[str, Any] = {}
        self._save_activation = target_layer.register_forward_hook(self._hook_act)
        self._save_gradient = target_layer.register_full_backward_hook(self._hook_grad)

    def _hook_act(self, _m, _i, out) -> None:
        self.activations["out"] = out.detach()

    def _hook_grad(self, _m, _gi, _go) -> None:
        import torch

        self.gradients["out"] = _go[0].detach() if isinstance(_go, tuple) else _go

    def __call__(self, x: Any, class_idx: Any) -> tuple[np.ndarray | None, Any]:
        import torch

        self.model.zero_grad()
        out = self.model(x)
        if class_idx == "referable":
            # Referable DR decision (grade >= 2): explain the log-sum-exp of the
            # referable LOGITS (not the softmax probs) — mirrors gradcam.py.
            score = torch.logsumexp(out[0, EXPLAIN_REFER_THRESHOLD:], dim=0)
        else:
            score = out[0, class_idx]
        score.backward()

        acts = self.activations.get("out")
        grads = self.gradients.get("out")
        if acts is None or grads is None:
            return None, None

        acts = acts[0]
        grads = grads[0]
        weights = grads.mean(dim=(1, 2), keepdim=True)
        cam = (weights * acts).sum(dim=0).clamp(min=0)
        cam = cam - cam.min()
        if cam.max() > 0:
            cam = cam / cam.max()

        H, W = x.shape[2], x.shape[3]
        cam = torch.nn.functional.interpolate(
            cam.unsqueeze(0).unsqueeze(0), size=(H, W), mode="bilinear", align_corners=False
        )[0, 0]
        return cam.detach().cpu().numpy(), out.detach().cpu().numpy()


def _to_rgb(image: np.ndarray) -> np.ndarray:
    """Normalize + resize the actual uploaded RGB image to model input."""
    import torch

    x = torch.from_numpy(
        np.ascontiguousarray(image).copy().transpose(2, 0, 1)
    ).float().div(255.0)
    from torchvision import transforms

    tf = transforms.Compose(
        [
            transforms.Resize((EXPLAIN_INPUT_SIZE, EXPLAIN_INPUT_SIZE)),
            transforms.Normalize(EXPLAIN_MEAN, EXPLAIN_STD),
        ]
    )
    return tf(x)


def _overlay_cam(image_rgb: np.ndarray, cam: np.ndarray) -> np.ndarray:
    """Blend jet-colormapped Grad-CAM over grayscale original (0.55/0.45
    blend, mirror of computeGradCAM.m / overlay.py)."""
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib import cm

    h, w = cam.shape[:2]
    base = np.asarray(
        np.mean(image_rgb, axis=2, dtype=np.float64)
    )
    if base.shape != (h, w):
        from PIL import Image

        base = np.asarray(
            Image.fromarray(base.astype(np.uint8)).resize((w, h), Image.BILINEAR)
        ).astype(np.float64)
    base = np.stack([base] * 3, axis=-1) / 255.0

    cam01 = np.clip(cam, 0.0, 1.0)
    heat = cm.jet(cam01)[..., :3]

    blended = 0.55 * base + 0.45 * heat
    return np.clip(blended * 255.0, 0, 255).astype(np.uint8)


def _evidence_overlay(image_rgb: np.ndarray) -> np.ndarray:
    """Honest lesion-evidence overlay: plain grayscale of the original.

    The pipeline has produced no per-lesion evidence markers for this image
    (prototype). It returns the unchanged grayscale — never fabricated lesion
    markers. Mirrors computeGradCAM.m evidence overlay path.
    """
    gray = np.asarray(np.mean(image_rgb, axis=2, dtype=np.float64))
    return np.stack([gray] * 3, axis=-1).astype(np.uint8)


def compute_explain(
    image: np.ndarray | Path | str,
) -> dict[str, Any] | None:
    """Compute real Grad-CAM attention for the actual uploaded image.

    *image* may be an HxWx3 RGB ndarray or a path to an image file (the
    screening service hands over the stored image path). The heatmap is
    generated for the model's actual predicted class on this image, not the
    referable aggregate decision. If the model/torch is unavailable or the
    image is not decodable this returns None (screening then reports
    honest-empty explainability). It NEVER fabricates attention.

    Returns (mirror of computeGradCAM.m contract):
      attentionImage  HxWx3 uint8
      evidenceOverlay HxWx3 uint8 (honest empty)
      note           'Model attention - not proof of causality'
    """
    rgb = _to_rgb_array(image)
    if rgb is None:
        return None
    model = _load_model()
    if model is None:
        return None

    try:
        import torch

        x = _to_rgb(rgb).unsqueeze(0)
        with torch.no_grad():
            logits = model(x)
        pred_idx = int(torch.argmax(logits[0]).item())

        gcam = _GradCAM(model, _anchor_layer(model))
        grad_cam, _ = gcam(x, pred_idx)

        if grad_cam is None:
            _logger.warning("explainability: no Grad-CAM produced — attention stays honest-empty")
            return None

        H, W = rgb.shape[:2]
        grad_cam = _resize_cam(grad_cam, (W, H))

        # Honest mirror of computeGradCAM.m (attention only when the cam
        # carries real content): a degenerate all-zero map means the model
        # found nothing to attend to. Rendering it would paint a flat dark
        # wash over the fundus AND still be served as "available" — neither is
        # honest, so it is treated exactly like "no attention".
        if not _has_attention_content(grad_cam):
            _logger.info(
                "explainability: degenerate (all-zero) Grad-CAM for %s — leaving honest-empty",
                _src_name(image),
            )
            return None

        attention = _overlay_cam(rgb, grad_cam)
        evidence = _evidence_overlay(rgb)

        return {
            "attentionImage": attention,
            "evidenceOverlay": evidence,
            "note": _EXPLAIN_NOTE,
        }
    except Exception as exc:  # noqa: BLE001 - advisory, never blocking
        _logger.warning("explainability: compute failed (%s) — attention stays honest-empty", exc)
        return None


def _src_name(image: Any) -> str:
    """Short label for log lines (filename, or "<array>" for ndarrays)."""
    if isinstance(image, (Path, str)):
        return Path(str(image)).name
    return "<array>"


def _has_attention_content(cam: np.ndarray) -> bool:
    """True when a Grad-CAM map actually highlights something.

    A degenerate all-zero (or effectively empty) map carries no attention and
    must never be rendered as an overlay — mirror of ``any(gradCam(:) > 0)``
    in computeGradCAM.m.
    """
    try:
        a = np.asarray(cam, dtype=np.float64)
    except Exception:
        return False
    return bool(a.size and float(a.max()) > 0.0)


def _to_rgb_array(image: np.ndarray | Path | str) -> np.ndarray | None:
    """Decode *image* (ndarray or file path) into a writable HxWx3 RGB array."""
    from PIL import Image

    if isinstance(image, (Path, str)):
        try:
            image = np.array(Image.open(str(image)).convert("RGB"))
        except Exception:
            return None
    if image is None:
        return None
    try:
        if image.size == 0 or image.ndim < 2:
            return None
    except Exception:
        return None
    if image.ndim == 2:
        image = np.stack([image] * 3, axis=-1)
    return np.asarray(image, dtype=np.uint8)


def _resize_cam(cam: np.ndarray, to: tuple[int, int]) -> np.ndarray:
    w, h = to
    if cam.shape[:2] == (h, w):
        return cam
    # Float bilinear resize with torch (same interpolator the cam already used)
    # — preserves the full 0..1 range without the 8-bit banding a PIL uint8
    # round-trip would introduce.
    import torch

    t = torch.from_numpy(cam).float().unsqueeze(0).unsqueeze(0)
    t = torch.nn.functional.interpolate(
        t, size=(h, w), mode="bilinear", align_corners=False
    )
    return t[0, 0].numpy()
