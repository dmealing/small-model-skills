#!/usr/bin/env python3
"""model-bench judge — score captured outputs (results.jsonl) with Gemini 2.5 Pro
against the per-task rubrics (tasks-hard.json). Blind + pointwise + verbosity-debiased.

Run after run-bench.sh. Prints a scorecard + per-task matrix + ranking, and writes
gemini-judgments.{json,jsonl} and reasons-by-model.md next to this script.

Usage: python3 judge.py [results.jsonl]
"""
import json
import os
import re
import sys
import subprocess
import urllib.request
import concurrent.futures

HERE = os.path.dirname(os.path.abspath(__file__))
TASKS = {t["id"]: t for t in json.load(open(f"{HERE}/tasks-hard.json"))}
RESULTS_FILE = sys.argv[1] if len(sys.argv) > 1 else f"{HERE}/results.jsonl"
# output fields contain raw newlines; jq -c . emits one clean record per line
RESULTS = [json.loads(line) for line in subprocess.check_output(
    ["jq", "-c", ".", RESULTS_FILE]).decode().splitlines() if line.strip()]
def _gemini_key():
    k = os.environ.get("GEMINI_API_KEY", "").strip()
    if k:
        return k
    for p in (os.path.expanduser("~/.config/small-model-skills/gemini.key"),):
        try:
            m = re.search(r"AIza[A-Za-z0-9_-]{20,}", open(p).read())
            if m:
                return m.group(0)
        except OSError:
            pass
    return ""
GKEY = _gemini_key()
assert GKEY, "no Gemini key: set GEMINI_API_KEY or put it in ~/.config/small-model-skills/gemini.key"
API = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent?key={GKEY}"

TEMPLATE = """You are a strict, neutral judge scoring ONE model response to a task, against a rubric.
Score ONLY by the rubric. Do NOT reward length, verbosity, confidence, or formatting — a longer or more confident answer is NOT better. A model that correctly did less can still score "full".

TASK PROMPT:
{prompt}

SCORING RUBRIC:
{rubric}

MODEL RESPONSE:
{output}

Reply with ONLY a compact JSON object, no markdown fences:
{{"score":"full|partial|fail","reason":"<one sentence citing the specific rubric clause that decided it>"}}"""

def judge(rec):
    t = TASKS.get(rec["id"], {})
    body = json.dumps({
        "contents": [{"parts": [{"text": TEMPLATE.format(
            prompt=t.get("prompt", ""), rubric=t.get("rubric", ""),
            output=rec.get("output", ""))}]}],
        "generationConfig": {"temperature": 0},
    }).encode()
    req = urllib.request.Request(API, data=body, headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            txt = json.load(r)["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        return {"model": rec["model"], "id": rec["id"], "score": "error", "reason": str(e)[:160]}
    txt = re.sub(r"^```(json)?|```$", "", txt.strip(), flags=re.M).strip()
    try:
        j = json.loads(txt)
        return {"model": rec["model"], "id": rec["id"],
                "score": j.get("score", "unclear"), "reason": j.get("reason", "?")}
    except Exception:
        return {"model": rec["model"], "id": rec["id"], "score": "unclear", "reason": txt[:160]}

judgments = []
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex:
    for j in ex.map(judge, RESULTS):
        judgments.append(j)
        sys.stderr.write(f"  {j['model']:<24} {j['id']:<24} -> {j['score']}\n")

json.dump(judgments, open(f"{HERE}/gemini-judgments.json", "w"), indent=2)
with open(f"{HERE}/gemini-judgments.jsonl", "w") as f:
    for j in judgments:
        f.write(json.dumps(j) + "\n")

PTS = {"full": 3, "partial": 2, "fail": 1, "unclear": 0, "error": 0}
models = sorted({j["model"] for j in judgments})
ids = [t["id"] for t in json.load(open(f"{HERE}/tasks-hard.json"))]

print("\n=== SCORECARD — Gemini 2.5 Pro judge, temp 0, pointwise vs rubric ===")
print(f"{'model':<26}{'full':>6}{'partial':>9}{'fail':>6}{'bad':>6}{'points':>9}")
agg = {}
for m in models:
    js = [j for j in judgments if j["model"] == m]
    full = sum(j["score"] == "full" for j in js)
    part = sum(j["score"] == "partial" for j in js)
    fail = sum(j["score"] == "fail" for j in js)
    bad = sum(j["score"] in ("unclear", "error") for j in js)
    pts = sum(PTS.get(j["score"], 0) for j in js)
    agg[m] = pts
    print(f"{m:<26}{full:>6}{part:>9}{fail:>6}{bad:>6}{pts:>4}/{3*len(js)}")

print("\n=== PER-TASK MATRIX (f=full, p=partial, F=fail) ===")
short = {"full": "f", "partial": "p", "fail": "F", "unclear": "?", "error": "x"}
print(f"{'task':<24}" + "".join(f"{m[-16:]:>18}" for m in models))
for tid in ids:
    row = f"{tid:<24}"
    for m in models:
        s = [j["score"] for j in judgments if j["id"] == tid and j["model"] == m]
        row += f"{(short.get(s[0], '-') if s else '-'):>18}"
    print(row)

ranked = sorted(agg.items(), key=lambda kv: kv[1], reverse=True)
print(f"\nRANKING: {' > '.join(f'{m} ({p})' for m, p in ranked)}")

with open(f"{HERE}/reasons-by-model.md", "w") as f:
    f.write("# Judge reasons by model\n\n")
    for m in models:
        f.write(f"## {m}\n\n")
        for tid in ids:
            j = next((j for j in judgments if j["id"] == tid and j["model"] == m), None)
            if j:
                f.write(f"- **{tid}** [{j['score']}]: {j['reason']}\n")
        f.write("\n")
print(f"\nDetailed reasons: {HERE}/reasons-by-model.md")
