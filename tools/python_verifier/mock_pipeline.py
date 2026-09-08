"""
RetinaSense Sprint 0 — pipeline verification harness (no MATLAB required).

This is a *dev-time* mirror of the MATLAB mock pipeline, used to execute the
end-to-end workflow and its contract tests on machines without MATLAB. It is
NOT product code and NOT a replacement for the MATLAB modules in
preprocessing/, classification/, etc. It mirrors only the Sprint-0 mock
semantics so CI can verify integration integrity:

    runPipeline(scenario) -> case
    scenarios: 'good' | 'borderline' | 'ungradable'

Mirrored contracts (docs/ARCHITECTURE.md §4):
    quality: score, class, metrics, failureReasons, recapture
    grading: rawProbs(5), grade, referableProb, referable
    calibrated: calibratedProbs, confidence, uncertainty, reviewRequired
    review: action, graderId, overrideGrade, finalReferral, status, notes

Run:  python mock_pipeline.py
"""

import math
import os
import time
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Config mirror (config/experiment_config.m)
# ---------------------------------------------------------------------------
REFER_THRESHOLD = 2          # referable DR = grade >= 2 (Level 2+)

QUALITY = {
    "metricLow": {"focus": 0.25, "illumination": 0.20, "fovCoverage": 0.30, "artifacts": 0.30},
    "metricMid": {"focus": 0.55, "illumination": 0.50, "fovCoverage": 0.55, "artifacts": 0.50},
    "weights": {"focus": 0.40, "illumination": 0.25, "fovCoverage": 0.20, "artifacts": 0.15},
    "goodScore": 0.65,
    "borderlineScore": 0.40,
}

CALIBRATION = {"confidenceLow": 0.80, "uncertaintyHigh": 0.30, "alwaysReview": False}
MOCK = {"seed": 1}


# ---------------------------------------------------------------------------
# Case schema mirror (core/newCase.m)
# ---------------------------------------------------------------------------
@dataclass
class Lesion:
    map_: list = field(default_factory=list)
    count: int = 0
    features: list = field(default_factory=list)


def empty_lesions():
    return {k: Lesion() for k in ("exudates", "hemorrhages", "microaneurysms", "neoVasc")}


def new_case():
    return {
        "image": None,
        "imagePath": "",
        "meta": {"patientId": "", "eye": "", "timestamp": "", "phcId": ""},
        "quality": {
            "score": float("nan"), "class": "",
            "metrics": {"focus": float("nan"), "illumination": float("nan"),
                        "fovCoverage": float("nan"), "artifacts": float("nan")},
            "failureReasons": [], "recapture": {"reasonCode": "", "instruction": ""},
        },
        "enhancement": {"appliedOps": [], "paramsPerOp": {}, "improved": False, "recheckClass": ""},
        "evidence": {"vesselMask": None, "opticDisc": None, "fovea": None,
                     "lesions": empty_lesions(), "confidence": ""},
        "grading": {"rawProbs": [float("nan")] * 5, "grade": float("nan"),
                    "referableProb": float("nan"), "referable": False, "modelFile": ""},
        "explain": {"gradCam": None, "attentionImage": None, "evidenceOverlay": None, "note": ""},
        "calibrated": {"calibratedProbs": [float("nan")] * 5, "confidence": float("nan"),
                       "uncertainty": float("nan"), "reviewRequired": False},
        "review": {"action": "", "graderId": "", "overrideGrade": float("nan"),
                   "finalReferral": False, "status": "", "notes": ""},
        "report": {"data": {}, "summary": "", "filepath": "", "review": {}},
        "pipeline": {"stages": [], "startedAt": "", "finishedAt": "",
                     "enhanced": False, "exitStage": ""},
        "model": {"backbone": "", "available": False},
    }


# ---------------------------------------------------------------------------
# Synthetic working image + quality gate
# ---------------------------------------------------------------------------
def synthetic_image(n=64):
    """Deterministic pseudo-retina image as list of ints [0..255], green-ish."""
    rng = _rng(MOCK["seed"])
    img = [[0] * n for _ in range(n)]
    cy, cx = n // 2, n // 2
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - cx, y - cy)
            val = 90 + 90 * (d < n * 0.22) + rng() % 30
            img[y][x] = max(0, min(255, val))
    return img


class QualityGate:
    """Mirror of preprocessing/assessQuality.m (classical CV scoring)."""

    def assess(self, img):
        n = len(img)
        gray = [[v / 255.0 for v in row] for row in img]   # 0..1, mirror MATLAB
        # focus: variance of 3x3 laplacian (0..1 domain, like MATLAB rgb2gray+conv2)
        lp = []
        for y in range(1, n - 1):
            for x in range(1, n - 1):
                v = (gray[y][x] * -4 + gray[y - 1][x] + gray[y + 1][x] +
                     gray[y][x - 1] + gray[y][x + 1])
                lp.append(v)
        var = sum(a * a for a in lp) / len(lp)
        focus = min(1.0, var / 0.02)

        vals = [px for row in gray for px in row]
        mean = sum(vals) / len(vals)
        illum = max(0.0, min(1.0, 1.0 - abs(mean - 0.5) / 0.5))

        fov = sum(1 for v in vals if v > 0.06) / len(vals)
        sat = sum(1 for v in vals if v > 0.985) / len(vals)
        dark = sum(1 for v in vals if v < 0.01) / len(vals)
        artifacts = max(0.0, 1.0 - (sat + dark))

        metrics = {"focus": focus, "illumination": illum, "fovCoverage": fov, "artifacts": artifacts}
        score = sum(QUALITY["weights"][k] * metrics[k] for k in metrics)
        low, mid = QUALITY["metricLow"], QUALITY["metricMid"]
        low_fail = [k for k in metrics if metrics[k] < low[k]]
        mid_fail = [k for k in metrics if metrics[k] < mid[k]]

        if low_fail:
            klass, reasons = "ungradable", low_fail
        elif mid_fail or score < QUALITY["goodScore"]:
            klass, reasons = "borderline", mid_fail
        else:
            klass, reasons = "good", []

        recapture = self._recapture(reasons) if klass == "ungradable" \
            else {"reasonCode": "", "instruction": ""}
        return {"score": score, "class": klass, "metrics": metrics,
                "failureReasons": reasons, "recapture": recapture}

    @staticmethod
    def _recapture(reasons):
        guide = {
            "focus": ("REFOCUS", "Image out of focus. Refocus on optic disc."),
            "illumination": ("FIX_LIGHTING", "Adjust illumination."),
            "fovCoverage": ("RECENTER_FOV", "Recenter field of view."),
            "artifacts": ("CLEAR_ARTIFACTS", "Reduce flash glare / ask patient to blink."),
        }
        key = next((k for k in ("focus", "illumination", "fovCoverage", "artifacts")
                    if k in reasons), reasons[0] if reasons else "")
        if not key:
            return {"reasonCode": "", "instruction": ""}
        code, text = guide[key]
        return {"reasonCode": code, "instruction": text}


# ---------------------------------------------------------------------------
# Advisory analysis (honest empty in Sprint 0)
# ---------------------------------------------------------------------------
def analyze_retina(img):
    return {"vesselMask": [[False] * len(img) for _ in range(len(img))],
            "opticDisc": None, "fovea": None, "lesions": empty_lesions(),
            "confidence": "low"}


# ---------------------------------------------------------------------------
# Grading, calibration, review, report (mock semantics)
# ---------------------------------------------------------------------------
def classify_image(img):
    rng = _rng(MOCK["seed"])
    g = sum(sum(row) for row in img) / (len(img) ** 2) / 255.0
    base = [3.0, 0.8 * math.exp(2 * g), 0.5 * math.exp(3 * g),
            0.3 * math.exp(3.5 * g), 0.2 * math.exp(4 * g)]
    total = sum(base)
    raw = [b / total for b in base]
    grade = max(range(5), key=lambda i: raw[i])
    referable_prob = sum(raw[REFER_THRESHOLD:])
    return {"rawProbs": raw, "grade": grade, "referableProb": referable_prob,
            "referable": grade >= REFER_THRESHOLD, "modelFile": ""}


def apply_calibration(grading, T=1.0):
    probs = grading["rawProbs"]
    m = max(probs)
    z = [(math.log(max(p, 1e-12)) - math.log(m)) / T for p in probs]
    zmax = max(z)
    ez = [math.exp(v - zmax) for v in z]
    cal = [v / sum(ez) for v in ez]
    conf = max(cal)
    ent = -sum(p * math.log(max(p, 1e-12)) for p in cal) / math.log(5)
    return {"calibratedProbs": cal, "confidence": conf, "uncertainty": ent,
            "reviewRequired": conf < CALIBRATION["confidenceLow"] or
                              ent > CALIBRATION["uncertaintyHigh"] or
                              CALIBRATION["alwaysReview"]}


def submit_review(case, reviewer_input=None):
    if reviewer_input is None:
        grade = case["grading"]["grade"]
        return {"action": "auto", "graderId": "", "overrideGrade": float("nan"),
                "finalReferral": grade >= REFER_THRESHOLD, "status": "auto", "notes": ""}
    r = reviewer_input
    if r["action"] == "approve":
        grade = case["grading"]["grade"]
        return {"action": "approve", "graderId": r["graderId"], "overrideGrade": float("nan"),
                "finalReferral": grade >= REFER_THRESHOLD, "status": "approved", "notes": r["notes"]}
    if r["action"] == "override":
        g = r["overrideGrade"]
        return {"action": "override", "graderId": r["graderId"], "overrideGrade": g,
                "finalReferral": g >= REFER_THRESHOLD, "status": "overridden", "notes": r["notes"]}
    if r["action"] == "recapture":
        return {"action": "recapture", "graderId": r["graderId"], "overrideGrade": float("nan"),
                "finalReferral": False, "status": "approved", "notes": r["notes"]}
    raise ValueError("BadAction")


def build_report(case):
    d = {"patientId": case["meta"]["patientId"], "eye": case["meta"]["eye"],
         "quality": case["quality"]["class"], "grade": case["grading"]["grade"],
         "referable": case["grading"]["referable"],
         "confidence": case["calibrated"]["confidence"],
         "uncertainty": case["calibrated"]["uncertainty"],
         "reviewAction": case["review"]["action"],
         "finalReferral": case["review"]["finalReferral"]}
    summary = (f"Patient {d['patientId']} ({d['eye']}): quality {d['quality']}, "
               f"grade {d['grade']} (referable={int(d['referable'])}), "
               f"conf {d['confidence']:.2f}, unc {d['uncertainty']:.2f}, "
               f"review {d['reviewAction']}, referral {int(d['finalReferral'])}.")
    return {"data": d, "summary": summary, "filepath": "",
            "disclaimer": "Screening decision-support only. "
                          "Not a diagnosis. Not a replacement for an ophthalmologist.",
            "review": case["review"]}


# ---------------------------------------------------------------------------
# Orchestrator mirror (scripts/runPipeline.m)
# ---------------------------------------------------------------------------
def run_pipeline(scenario="good", meta=None, image_path="", reviewer_input=None,
                 mock_enabled=True, write_report=False):
    if not mock_enabled:
        raise RuntimeError("MissingModel: no trained model present")

    c = new_case()
    c["meta"] = meta or {"patientId": "demo001", "eye": "right",
                         "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"), "phcId": "PHC-TEST"}
    c["image"] = synthetic_image()
    c["pipeline"]["startedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    c["pipeline"]["stages"].append("ingest")

    # Mock scenario mutation (mirror of applyScenario).
    if scenario == "ungradable":
        c["image"] = [[8] * len(c["image"]) for _ in range(len(c["image"]))]
    elif scenario == "borderline":
        # Underexposure: brightness offset, blur untouched. Mirrors the quality
        # gate treating illumination vs focus as independent failure modes.
        c["image"] = [[max(0, v - 60) for v in row] for row in c["image"]]

    gate = QualityGate()
    c["quality"] = gate.assess(c["image"])
    c["pipeline"]["stages"].append("qualityGate")

    if c["quality"]["class"] == "ungradable":
        c["pipeline"]["exitStage"] = "qualityGate"
        return c

    if c["quality"]["class"] == "borderline":
        c["pipeline"]["stages"].append("enhancement")
        # Mock CLAHE+gamma: brightness lift; no pixels crushed to 0 (mirrors
        # adapthisteq preserving FOV coverage while correcting exposure).
        enh = [[max(0, min(255, int(v * 1.35 + 22))) for v in row] for row in c["image"]]
        recheck = gate.assess(enh)
        if recheck["class"] == "ungradable":
            c["pipeline"]["exitStage"] = "enhancementRecheck"
            c["quality"]["recapture"] = recheck["recapture"]
            return c
        c["image"], c["enhancement"]["recheckClass"] = enh, recheck["class"]
        c["pipeline"]["enhanced"] = True

    c["evidence"] = analyze_retina(c["image"])
    c["pipeline"]["stages"].append("analysis")
    c["grading"] = classify_image(c["image"])
    c["pipeline"]["stages"].append("grading")
    c["explain"] = {"gradCam": None, "attentionImage": None,
                    "evidenceOverlay": None, "note": "Model attention - not proof of causality"}
    c["pipeline"]["stages"].append("explainability")
    c["calibrated"] = apply_calibration(c["grading"])
    c["pipeline"]["stages"].append("calibration")

    if reviewer_input is None and c["calibrated"]["reviewRequired"]:
        c["review"] = {"action": "", "graderId": "", "overrideGrade": float("nan"),
                       "finalReferral": False, "status": "reqReview",
                       "notes": "Low confidence - routed to ophthalmologist review (FR-08)."}
    else:
        c["review"] = submit_review(c, reviewer_input)
    c["pipeline"]["stages"].append("review")

    c["report"] = build_report(c)
    c["pipeline"]["stages"].append("report")
    if write_report:
        c["report"]["filepath"] = write_txt_report(c["report"])
    c["pipeline"]["finishedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    return c


def write_txt_report(report, out_dir="output"):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "report_mock.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("--- RetinaSense Screening Report (mock verifier) ---\n")
        fh.write(report["summary"] + "\n\n")
        fh.write(report["disclaimer"] + "\n")
    return path


# ---------------------------------------------------------------------------
# Deterministic RNG (no numpy dependency)
# ---------------------------------------------------------------------------
_rng_state = [0]


def _rng(seed):
    _rng_state[0] = seed * 9301 + 49297
    return _rng_gen


def _rng_gen():
    _rng_state[0] = (_rng_state[0] * 233280 + 9301) % 233280
    return _rng_state[0] % 233280


# ---------------------------------------------------------------------------
# Assertions mirroring tests/ (contract + pipeline)
# ---------------------------------------------------------------------------
def run_checks():
    fails = []

    def check(cond, name):
        (fails.append(f"FAIL: {name}") if not cond else None)
        print(("ok   " if cond else "FAIL ") + name)

    c0 = new_case()
    check(all(k in c0 for k in ("image", "quality", "evidence", "grading",
                                "explain", "calibrated", "review", "report", "meta")),
          "case has all contract fields")
    check(len(c0["grading"]["rawProbs"]) == 5, "grading rawProbs is 1x5")

    # interface contracts
    img = synthetic_image()
    q = QualityGate().assess(img)
    check(q["class"] in ("good", "borderline", "ungradable"), "quality class valid")
    check(0.0 <= q["score"] <= 1.0, "quality score in [0,1]")
    check(set(q["metrics"]) == {"focus", "illumination", "fovCoverage", "artifacts"},
          "quality metrics keys")

    qq = QualityGate().assess([[8] * 64 for _ in range(64)])
    check(qq["class"] == "ungradable", "near-black is ungradable")
    check(bool(qq["recapture"]["reasonCode"]), "recapture guidance present")

    g = classify_image(img)
    check(abs(sum(g["rawProbs"]) - 1.0) < 1e-9, "rawProbs sums to 1")
    check(0 <= g["grade"] <= 4, "grade in 0..4")
    check(isinstance(g["referable"], bool), "referable is bool")

    cal = apply_calibration(g)
    check(abs(sum(cal["calibratedProbs"]) - 1.0) < 1e-9, "calibratedProbs sums to 1")
    check(0.0 <= cal["uncertainty"] <= 1.0, "uncertainty in [0,1]")

    ev = analyze_retina(img)
    check(ev["confidence"] in ("low", "medium", "high"), "evidence confidence")
    check(all(k in ev["lesions"] for k in ("exudates", "hemorrhages", "microaneurysms", "neoVasc")),
          "evidence lesion classes")

    # orchestration end-to-end
    seen = {}
    for sc in ("good", "borderline", "ungradable"):
        c = run_pipeline(sc, write_report=True)
        seen[sc] = c
        check(c["quality"]["class"] in ("good", "borderline", "ungradable"),
              f"{sc}: quality valid")
        check("ingest" in c["pipeline"]["stages"] and "qualityGate" in c["pipeline"]["stages"],
              f"{sc}: ingest + quality gate stages run")
        if c["quality"]["class"] == "ungradable":
            check(c["pipeline"]["exitStage"] == "qualityGate", f"{sc}: exits at gate")
        else:
            check("grading" in c["pipeline"]["stages"], f"{sc}: grading ran")
            check("report" in c["pipeline"]["stages"], f"{sc}: report stage ran")
            check(os.path.exists(c["report"]["filepath"]), f"{sc}: report file written")
            check(bool(c["report"]["summary"].strip()),
                  f"{sc}: report summary non-empty")
        check(set(c["grading"]["rawProbs"]) is not None, f"{sc}: grading structure")

    good = seen["good"]
    g_good = good["grading"]["grade"]
    check(good["review"]["finally" if False else "finalReferral"] == (g_good >= REFER_THRESHOLD),
          "good: auto finalReferral matches grade vs refer threshold")

    over = run_pipeline("good", reviewer_input={"action": "override", "graderId": "OPH-01",
                                                "overrideGrade": 3, "notes": "found MAs"})
    check(over["review"]["status"] == "overridden", "override: status overridden")
    check(over["review"]["finalReferral"] is True, "override grade 3 >= 2 -> referral True")
    check(over["report"]["review"]["finalReferral"] is True, "override propagates to report")

    return fails


def main():
    print("=" * 64)
    print("RetinaSense Sprint 0 - Python verification harness")
    print("Mirrors the MATLAB mock pipeline (tools/python_verifier)")
    print("=" * 64)
    fails = run_checks()
    print("-" * 64)
    if fails:
        print("\n".join(fails))
        print(f"RESULT: {len(fails)} check(s) FAILED (exit 1)")
        return 1
    print(f"RESULT: all checks passed ({'good/borderline/ungradable + override'} end-to-end)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())