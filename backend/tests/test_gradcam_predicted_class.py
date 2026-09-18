from __future__ import annotations

import numpy as np
import pytest
from PIL import Image

import app.services.explainability as explainability


class DummyLayer:
    def register_forward_hook(self, hook):
        return None

    def register_full_backward_hook(self, hook):
        return None


class DummyModel:
    def __init__(self):
        self.calls = []
        self.layer4 = DummyLayer()

    def zero_grad(self):
        pass

    def __call__(self, x):
        import torch

        logits = torch.full((1, 5), -1.0, dtype=torch.float32)
        logits[0, 0] = 10.0
        logits[0, 1] = -0.5
        logits[0, 2] = -2.0
        logits[0, 3] = -3.0
        logits[0, 4] = -4.0
        return logits

    def eval(self):
        pass


def test_compute_explain_uses_predicted_class(monkeypatch, tmp_path):
    image_path = tmp_path / "aptos_test.png"
    Image.new("RGB", (32, 32), color=(255, 0, 0)).save(image_path)

    dummy_model = DummyModel()
    monkeypatch.setattr(explainability, "_load_model", lambda: dummy_model)

    seen = {}

    class FakeGradCAM:
        def __init__(self, model, target_layer):
            pass

        def __call__(self, x, class_idx):
            seen["class_idx"] = class_idx
            return np.ones((x.shape[2], x.shape[3]), dtype=np.float32), np.ones((1, 5), dtype=np.float32)

    monkeypatch.setattr(explainability, "_GradCAM", FakeGradCAM)
    monkeypatch.setattr(explainability, "_has_attention_content", lambda cam: True)
    monkeypatch.setattr(explainability, "_overlay_cam", lambda rgb, cam: np.zeros((32, 32, 3), dtype=np.uint8))
    monkeypatch.setattr(explainability, "_evidence_overlay", lambda rgb: np.zeros((32, 32, 3), dtype=np.uint8))

    result = explainability.compute_explain(str(image_path))

    assert result is not None
    assert seen["class_idx"] == 0
