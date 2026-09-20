#!/usr/bin/env python3
"""Compare two or more ds4-eval run directories case by case.

A single run conflates two things a fixed-nonce run cannot: the model's real
accuracy, and whichever reasoning path the sampler happened to take. This
turns N results.json files into a per-case stability read and a handful of
run-level numbers — see README.md for how to read the output.

  ./compare.py ../../results/glm5.3-flash/measure-seed1 \
               ../../results/glm5.3-flash/measure-seed2 [...]
"""
import json
import statistics
import sys
from pathlib import Path


def load_run(run_dir: Path) -> dict:
    data = json.loads((run_dir / "results.json").read_text())
    by_case = {f"{c['source']}/{c['id']}": c for c in data["cases"]}
    return {"dir": run_dir, "summary": data["summary"], "cases": by_case}


def classify(flags: list) -> str:
    if all(flags):
        return "stable-correct"
    if not any(flags):
        return "stable-incorrect"
    return "unstable"


def compare(run_dirs: list) -> dict:
    runs = [load_run(d) for d in run_dirs]
    common = set(runs[0]["cases"])
    for r in runs[1:]:
        common &= set(r["cases"])
    missing = set()
    for r in runs:
        missing |= set(r["cases"]) - common

    cases_out = {}
    for key in sorted(common):
        per_run, flags = [], []
        for r in runs:
            c = r["cases"][key]
            per_run.append({
                "run": str(r["dir"]),
                "correct": bool(c["correct"]),
                "completion_tokens": c.get("completion_tokens"),
                "seconds": c.get("seconds"),
                "forced": bool(c.get("forced", False)),
                "finish_reason": c.get("finish_reason"),
            })
            flags.append(bool(c["correct"]))
        cases_out[key] = {"classification": classify(flags), "runs": per_run}

    percentages = [r["summary"]["percentage"] for r in runs]
    mean_score = round(statistics.fmean(percentages), 2) if percentages else 0.0
    spread = round(statistics.pstdev(percentages), 2) if len(percentages) > 1 else 0.0
    unstable = sum(1 for c in cases_out.values() if c["classification"] == "unstable")
    forced_total = sum(sum(1 for pr in c["runs"] if pr["forced"]) for c in cases_out.values())
    truncated_total = sum(sum(1 for pr in c["runs"] if pr["finish_reason"] == "length")
                          for c in cases_out.values())
    correct_tokens = [pr["completion_tokens"] for c in cases_out.values() for pr in c["runs"]
                      if pr["correct"] and pr["completion_tokens"] is not None]
    tokens_per_correct = round(statistics.fmean(correct_tokens)) if correct_tokens else None

    summary = {
        "runs": [str(r["dir"]) for r in runs],
        "cases_compared": len(common),
        "cases_missing_from_some_run": sorted(missing),
        "mean_score": mean_score, "score_spread": spread,
        "unstable": unstable, "forced_total": forced_total,
        "truncated_total": truncated_total, "tokens_per_correct": tokens_per_correct,
    }
    return {"summary": summary, "cases": cases_out}


def print_table(result: dict) -> None:
    s = result["summary"]
    print(f"runs: {len(s['runs'])}   cases compared: {s['cases_compared']}")
    for r in s["runs"]:
        print(f"  {r}")
    if s["cases_missing_from_some_run"]:
        print(f"  ({len(s['cases_missing_from_some_run'])} case(s) missing from at "
              f"least one run, excluded from the comparison)")
    print()
    for key, c in result["cases"].items():
        per_run = " ".join(f"{pr['completion_tokens']}t/{pr['seconds']}s" for pr in c["runs"])
        print(f"  {c['classification']:<16} {key:<34} {per_run}")
    print()
    print(f"mean score {s['mean_score']}%   spread {s['score_spread']}pp   "
          f"unstable {s['unstable']}/{s['cases_compared']}   "
          f"forced {s['forced_total']}   truncated {s['truncated_total']}   "
          f"tokens/correct {s['tokens_per_correct']}")


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <run-dir> <run-dir> [...]", file=sys.stderr)
        return 1
    run_dirs = [Path(a) for a in sys.argv[1:]]
    result = compare(run_dirs)
    print_table(result)
    out = Path("comparison.json")
    out.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    print(f"-> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
