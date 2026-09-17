"""Full-stack smoke verification — FRONTEND-BACKEND-MATLAB chain, live.

Verifies that a browser-style client (the Vite dev origin) can drive the
REAL RetinaSense stack end to end:

  [A] GET  /api/health                       + CORS headers for :5173 origin
  [B] POST /api/auth/login                   bearer session
  [C] GET  /api/auth/me                      persisted-session validation
  [D] POST /api/cases                        create a case
  [E] POST /api/cases/{id}/screen            REAL MATLAB pipeline on a real
                                             APTOS fundus -> completed grade
  [F] POST /api/cases/{id}/screen            REAL gate on an out-of-focus
                                             IDRiD image -> recapture branch
  [G] GET  image + gradcam artifact          real PNG blobs
  [H] POST report / GET report / GET pdf    valid PDF
  [I] POST review (approve)                  human-in-the-loop final decision

Prints PASS/FAIL per step and exits non-zero if anything fails. Observes the
real pipeline only — never force-invents values.
"""
from __future__ import annotations

import sys
from pathlib import Path

import httpx

BASE = "http://127.0.0.1:8000"
FRONT_ORIGIN = "http://localhost:5173"
TIMEOUT = 300.0

USERNAME = "doctor"
PASSWORD = "doctor123"

GOOD_IMAGE = Path(r"D:\Projects\RetinaSense\data\raw\aptos\images\0\img_0003.png")
BAD_IMAGE = Path(r"D:\Projects\RetinaSense\data\raw\IDRiD\C. Localization\C. Localization\1. Original Images\b. Testing Set\IDRiD_001.jpg")

failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"[{('PASS' if ok else 'FAIL')}] {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures.append(name)


def main() -> int:
    c = httpx.Client(base_url=BASE, timeout=TIMEOUT, follow_redirects=True)

    # [A] health + CORS (the thing that actually connects the browser to the API)
    r = c.get("/api/health", headers={"Origin": FRONT_ORIGIN})
    acao = r.headers.get("access-control-allow-origin")
    health = r.json()
    check(
        "A1 health ok + MATLAB engine real",
        r.status_code == 200 and health.get("status") == "ok" and health.get("matlabEngine") is True,
        f'matlabEngine={health.get("matlabEngine")}',
    )
    check("A2 CORS allows frontend origin", acao in (FRONT_ORIGIN, "*"), f"ACAO={acao or '-'}")

    # [B] + [C] auth
    r = c.post("/api/auth/login", json={"username": USERNAME, "password": PASSWORD})
    check("B login (doctor)", r.status_code == 200 and bool(r.json().get("token")))
    token = r.json()["token"]
    c.headers["Authorization"] = f"Bearer {token}"
    r = c.get("/api/auth/me")
    me = r.json()
    check(
        "C /api/auth/me honours persisted session",
        r.status_code == 200 and me.get("username") == USERNAME and me.get("role") == "ophthalmologist",
        f'user={me.get("username")} role={me.get("role")}',
    )

    # [D] create case
    r = c.post("/api/cases", data={"patientId": "SMOKE-PATIENT", "eye": "OD", "phcId": "PHC-SMOKE"})
    case_id = r.json()["caseId"]
    check("D create case", r.status_code == 201 and bool(case_id), case_id)

    # [E] real MATLAB screening on a real accepted APTOS image
    with GOOD_IMAGE.open("rb") as fh:
        r = c.post(
            f"/api/cases/{case_id}/screen",
            files={"image": (GOOD_IMAGE.name, fh, "image/png")},
            data={"patientId": "SMOKE-PATIENT", "eye": "OD", "phcId": "PHC-SMOKE"},
        )
    s = r.json()
    ai = s.get("aiPrediction") or {}
    expl = s.get("explainability") or {}
    check(
        "E real screening completes + AI grade from real model",
        s.get("status") == "completed" and ai.get("grade") is not None,
        f'status={s.get("status")} grade={ai.get("grade")} conf={ai.get("confidence")} q={s.get("quality", {}).get("score")}',
    )
    check(
        "E2 real Grad-CAM artifact referenced",
        expl.get("gradCamAvailable") is True and expl.get("gradCamPath"),
        expl.get("gradCamPath"),
    )

    # [F] the honest gate branch on an out-of-focus image
    other = c.post("/api/cases", data={"patientId": "SMOKE-PATIENT", "eye": "OS", "phcId": "PHC-SMOKE"})
    other_id = other.json()["caseId"]
    with BAD_IMAGE.open("rb") as fh:
        r = c.post(
            f"/api/cases/{other_id}/screen",
            files={"image": (BAD_IMAGE.name, fh, "image/jpeg")},
            data={"patientId": "SMOKE-PATIENT", "eye": "OS", "phcId": "PHC-SMOKE"},
        )
    fb = r.json()
    check(
        "F quality gate honestly rejects ungradable (no fabricated grade)",
        fb.get("status") == "recapture_required" and (fb.get("aiPrediction") or {}).get("grade") is None,
        f'status={fb.get("status")} reasons={fb.get("quality", {}).get("failureReasons")}',
    )

    # [G] real blobs: fundus image + Grad-CAM PNG
    r = c.get(f"/api/cases/{case_id}/image", headers={"Origin": FRONT_ORIGIN})
    png_ok = r.status_code == 200 and r.content[:8] == b"\x89PNG\r\n\x1a\n"
    check("G1 fundus image served as PNG", png_ok, f"bytes={len(r.content)}")

    gcam_name = expl["gradCamPath"].rsplit("/", 1)[-1]
    r = c.get(f"/api/cases/{case_id}/artifacts/{gcam_name}", headers={"Origin": FRONT_ORIGIN})
    gcam_ok = r.status_code == 200 and r.content[:8] == b"\x89PNG\r\n\x1a\n"
    check("G2 Grad-CAM artifact served as PNG", gcam_ok, f"artifact={gcam_name} bytes={len(r.content)}")

    # [H] report + PDF
    r = c.post(f"/api/cases/{case_id}/report")
    payload = r.json().get("report") or {}
    check(
        "H1 report generated from real screening",
        r.status_code == 200 and payload.get("status") == "completed" and (payload.get("aiPrediction") or {}).get("grade") is not None,
        f'summary={r.json().get("summary", "")[:70]!r}',
    )
    r = c.get(f"/api/cases/{case_id}/report/pdf", headers={"Origin": FRONT_ORIGIN})
    pdf_ok = r.status_code == 200 and r.content[:5] == b"%PDF-"
    check("H2 PDF report downloadable", pdf_ok, f"bytes={len(r.content) if pdf_ok else '-'}")

    # [I] human review (ophthalmologist endpoint, signed by doctor)
    r = c.post(f"/api/cases/{case_id}/review", json={"action": "approve", "reviewerId": USERNAME, "notes": "smoke approve"})
    rev = r.json()
    fd = rev.get("finalDecision") or {}
    check(
        "I human review completes (approve)",
        r.status_code == 200 and fd.get("grade") == ai.get("grade") and fd.get("referral") is not None,
        f'finalGrade={fd.get("grade")} referral={fd.get("referral")}',
    )

    # [J] list/stats reflect stored cases
    r = c.get("/api/cases", headers={"Origin": FRONT_ORIGIN})
    list_ok = r.status_code == 200 and any(item["caseId"] == case_id for item in r.json())
    check("J case list reflects real store", list_ok, f"cases={len(r.json())}")
    r = c.get("/api/cases/stats", headers={"Origin": FRONT_ORIGIN})
    check("K case stats reflect real store", r.status_code == 200 and r.json().get("totalCases", 0) > 0)

    print()
    if failures:
        print(f"SMOKE FAILED: {failures}")
        return 1
    print("FULL-STACK SMOKE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())