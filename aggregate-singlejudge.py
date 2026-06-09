#!/usr/bin/env python3
"""Aggregate single-judge ratings JSONs (written by Opus subagents) into a
per-chunk + total score for a model dir. Averages over multiple judge ROUNDS
per chunk: chunkN-ratings.json (round1) + chunkN-ratings-r2.json + r3 ...
Mirrors judge-knowledge.py scoring (pass=2/partial=1/fail=0).

Usage: python3 aggregate-singlejudge.py results/<model-dir> [run]
"""
import json, sys, glob, re
from pathlib import Path

CHUNK_TOPIC = {
    1: "networking / linux", 2: "k8s / dev", 3: "opentofu / ansible",
    4: "go / rust", 5: ".net / python", 6: "js / bash / powershell",
    7: "app-arch / on-prem", 8: "cloud / OT", 9: "scenarios (Part A/B/C)",
}

model_dir = Path(sys.argv[1])
run = sys.argv[2] if len(sys.argv) > 2 else "1"
run_dir = model_dir / f"run{run}"

def round_files(c):
    base = run_dir / f"chunk{c}-ratings.json"
    extra = sorted(run_dir.glob(f"chunk{c}-ratings-r*.json"))
    return ([base] if base.exists() else []) + list(extra)

# per chunk: list of (round_pts, round_max)
chunk_rounds = {}
n_rounds_seen = 0
for c in range(1, 10):
    rounds = []
    for rf in round_files(c):
        data = json.loads(rf.read_text())
        pts = sum(int(v.get("points", 0)) for v in data.values())
        rounds.append((pts, len(data) * 2))
    chunk_rounds[c] = rounds
    n_rounds_seen = max(n_rounds_seen, len(rounds))

print(f"\n=== {model_dir.name} (run{run}, {n_rounds_seen} judge round(s) averaged) ===")
print(f"{'Chunk':<6}{'Topic':<26}{'Avg score':>16}{'  rounds':<14}")
grand_avg = grand_max = 0.0
prose_avg = prose_max = 0.0
for c in range(1, 10):
    rounds = chunk_rounds[c]
    if not rounds:
        print(f"{c:<6}{CHUNK_TOPIC[c]:<26}{'MISSING':>16}")
        continue
    mx = rounds[0][1]
    avg = sum(p for p, _ in rounds) / len(rounds)
    rlist = "/".join(str(p) for p, _ in rounds)
    print(f"{c:<6}{CHUNK_TOPIC[c]:<26}{f'{avg:.1f}/{mx} ({100*avg/mx:.1f}%)':>16}  [{rlist}]")
    grand_avg += avg; grand_max += mx
    if c <= 8:
        prose_avg += avg; prose_max += mx
print("-" * 58)
if prose_max:
    print(f"{'':<6}{'knowledge prose (1-8)':<26}{f'{prose_avg:.1f}/{prose_max:.0f} ({100*prose_avg/prose_max:.1f}%)':>16}")
if grand_max:
    print(f"{'':<6}{'TOTAL':<26}{f'{grand_avg:.1f}/{grand_max:.0f} ({100*grand_avg/grand_max:.1f}%)':>16}")
