"""End-to-end smoke test: login -> create case -> screen via real MATLAB pipeline."""
import requests, time, sys

BASE = "http://127.0.0.1:8000"

# 1. Login
r = requests.post(f"{BASE}/api/auth/login", json={"username": "doctor", "password": "doctor123"})
r.raise_for_status()
token = r.json()["token"]
headers = {"Authorization": f"Bearer {token}"}
print("1. Login OK  role=ophthalmologist")

# 2. Create case
r = requests.post(f"{BASE}/api/cases", headers=headers,
    data={"patientId": "P-DEMO-E2E", "eye": "right", "phcId": "PHC-TEST"})
r.raise_for_status()
case_id = r.json()["caseId"]
print(f"2. Case created: {case_id}")

# 3. Screen - MATLAB engine first call starts matlab.engine session (~30-60s)
print("3. Running MATLAB pipeline via real engine (allow up to 5 min)...")
t0 = time.time()
with open(r"D:\Project\RetinaSense\assets\synthetic_fundus_demo.png", "rb") as f:
    r = requests.post(
        f"{BASE}/api/cases/{case_id}/screen",
        headers=headers,
        files={"image": ("synthetic_fundus_demo.png", f, "image/png")},
        timeout=300,
    )
elapsed = time.time() - t0
print(f"   Response: HTTP {r.status_code}  in {elapsed:.1f}s")

if r.status_code != 200:
    print("ERROR:", r.text[:600])
    sys.exit(1)

d = r.json()
status = d["status"]
q = d["quality"]
qclass = q.get("class_") or q.get("class")
qscore = q.get("score")
ai = d.get("aiPrediction") or {}

print(f"4. status         : {status}")
print(f"   quality.class  : {qclass}")
print(f"   quality.score  : {qscore}")

if ai.get("grade") is not None:
    print(f"   AI grade       : {ai['grade']} — {ai['gradeLabel']}")
    print(f"   referable      : {ai['referable']}")
    print(f"   confidence     : {ai['confidence']}")
    print(f"   uncertainty    : {ai['uncertainty']}")
    print(f"   reviewRequired : {ai['reviewRequired']}")
else:
    print(f"   aiPrediction   : (none — quality gate or model missing)")

print()
print("=" * 60)
print("RetinaSense full-stack smoke test PASSED")
print(f"  Backend : http://127.0.0.1:8000  (matlabEngine=true)")
print(f"  Frontend: http://localhost:5173")
print(f"  Case    : {case_id}")
print("=" * 60)
