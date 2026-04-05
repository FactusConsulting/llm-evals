#!/usr/bin/env python3
"""
Score knowledge eval responses using Claude Opus 4.6.

For each run × chunk combination, calls Opus to score each answer (pass/partial/fail),
writes per-question evaluation files via evaluate-chunk.py, then prints aggregate scores.

Usage:
    python3 judge-knowledge.py --model-dir results/gemma4-4b [--runs 1 2 3 4 5] [--chunks 1-9]
    python3 judge-knowledge.py --model-dir results/gemma4-4b --runs 1 --chunks 1  # single test

Environment:
    ANTHROPIC_API_KEY  Required.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
JUDGE_MODEL = "claude-opus-4-6"

CHUNK_NAMES = {
    1: "chunk1-networking-linux.txt",
    2: "chunk2-k8s-dev.txt",
    3: "chunk3-opentofu-ansible.txt",
    4: "chunk4-go-rust.txt",
    5: "chunk5-dotnet-python.txt",
    6: "chunk6-js-bash-powershell.txt",
    7: "chunk7-apparch-onprem.txt",
    8: "chunk8-cloud-ot.txt",
    9: "chunk9-scenarios.txt",
}

# Section metadata for each question prefix
SECTION_MAP = {
    "N": ("Networking", None),
    "L": ("Linux", None),
    "K": ("Kubernetes", None),
    "D": ("Docker/Dev", None),
    "T": ("OpenTofu", None),
    "A": ("Ansible", None),
    "G": ("Go", None),
    "R": ("Rust", None),
    "P": ("Python/.NET", None),
    "B": ("Bash/JS/PS", None),
    "C": ("Scenarios", None),
    "S": ("Scenarios", None),
    "I": ("On-Prem/Arch", None),
    "M": ("Monitoring", None),
    "X": ("Misc", None),
}


def call_opus(api_key: str, prompt: str, max_tokens: int = 8192) -> str:
    payload = {
        "model": JUDGE_MODEL,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=data,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read().decode())
    return body["content"][0]["text"]


def extract_question_ids(chunk_text: str) -> list[str]:
    """Extract ordered question IDs from chunk text."""
    ids = []
    for line in chunk_text.splitlines():
        m = re.match(r'^([A-Z]\d+)\s*[—–-]', line.strip())
        if m:
            ids.append(m.group(1))
    return ids


def get_difficulty(chunk_text: str, qid: str) -> str:
    for line in chunk_text.splitlines():
        if line.strip().startswith(qid + " ") or line.strip().startswith(qid + "—") or line.strip().startswith(qid + " —"):
            m = re.search(r'(Easy|Medium|Hard)', line, re.IGNORECASE)
            if m:
                return m.group(1).lower()
    return "medium"


def get_section(qid: str) -> str:
    prefix = re.match(r'^([A-Z]+)', qid)
    if prefix:
        return SECTION_MAP.get(prefix.group(1), ("Unknown", None))[0]
    return "Unknown"


def score_chunk(api_key: str, chunk_text: str, response_text: str,
                model_name: str, chunk_num: int, run_num: int) -> dict:
    """Score one run's response to one chunk. Returns {qid: rating_dict}."""

    question_ids = extract_question_ids(chunk_text)
    qids_str = ", ".join(question_ids)

    prompt = f"""You are an expert technical evaluator scoring answers to infrastructure/DevOps knowledge questions.

QUESTIONS (Chunk {chunk_num}):
{chunk_text}

MODEL RESPONSE:
{response_text}

Score each answer. Question IDs in this chunk: {qids_str}

For each question:
- pass = 2 pts: answer is correct and complete, covering all key technical points
- partial = 1 pt: answer is mostly correct but missing an important detail, or has a minor error
- fail = 0 pts: answer is wrong, confused, or missing

Pay close attention to:
- Exact calculations (IP subnet math, MTU calculations, etc.)
- Specific command syntax
- Whether the model answered what was actually asked (not a related but different question)

Respond ONLY with a JSON object. No markdown, no explanation. Format:
{{
  "Q_ID": {{
    "rating": "pass|partial|fail",
    "points": 2|1|0,
    "correct": ["key point covered", ...],
    "missing": ["key point omitted", ...],
    "wrong": ["factual error", ...],
    "justification": "one sentence"
  }},
  ...
}}

Include every question ID. Be strict about factual accuracy."""

    try:
        raw = call_opus(api_key, prompt, max_tokens=8192)
        # Strip markdown fencing if present
        raw = re.sub(r'^```(?:json)?\s*', '', raw.strip())
        raw = re.sub(r'\s*```$', '', raw.strip())
        ratings = json.loads(raw)
    except Exception as e:
        print(f"  [ERROR chunk{chunk_num}/run{run_num}] parse failed: {e}", file=sys.stderr)
        # Return zero scores for all questions
        ratings = {
            qid: {"rating": "fail", "points": 0, "correct": [], "missing": ["scoring error"], "wrong": [], "justification": f"API/parse error: {e}"}
            for qid in question_ids
        }

    # Normalize and add metadata
    result = {}
    for qid in question_ids:
        r = ratings.get(qid, {})
        result[qid] = {
            "section": get_section(qid),
            "difficulty": get_difficulty(chunk_text, qid),
            "model": model_name,
            "rating": r.get("rating", "fail"),
            "points": int(r.get("points", 0)),
            "correct": r.get("correct", []),
            "missing": r.get("missing", []),
            "wrong": r.get("wrong", []),
            "justification": r.get("justification", ""),
        }
    return result


def judge_run_chunk(api_key: str, model_dir: Path, model_name: str,
                    run: int, chunk_num: int) -> tuple[int, int, int, int]:
    """Judge one run × chunk. Returns (run, chunk, total_pts, max_pts)."""
    chunk_file = model_dir / "chunks" / CHUNK_NAMES[chunk_num]
    response_file = model_dir / f"run{run}" / f"chunk{chunk_num}-response.txt"
    eval_dir = model_dir / f"run{run}" / "evaluations"
    ratings_file = model_dir / f"run{run}" / f"chunk{chunk_num}-ratings.json"

    if not chunk_file.exists():
        print(f"  [SKIP] chunk{chunk_num} question file not found", file=sys.stderr)
        return run, chunk_num, 0, 0

    if not response_file.exists():
        print(f"  [SKIP] run{run}/chunk{chunk_num} response not found", file=sys.stderr)
        return run, chunk_num, 0, 0

    # Check if already scored
    question_ids = extract_question_ids(chunk_file.read_text())
    if eval_dir.exists() and question_ids:
        first_qid = question_ids[0]
        if (eval_dir / f"{first_qid}.json").exists():
            # Load existing scores
            total = sum(
                json.loads((eval_dir / f"{qid}.json").read_text()).get("points", 0)
                for qid in question_ids
                if (eval_dir / f"{qid}.json").exists()
            )
            print(f"  [SKIP already scored] run{run}/chunk{chunk_num}: {total}/{len(question_ids)*2}")
            return run, chunk_num, total, len(question_ids) * 2

    print(f"  [JUDGE] run{run}/chunk{chunk_num} ({len(question_ids)} questions)...")
    ratings = score_chunk(
        api_key,
        chunk_file.read_text(),
        response_file.read_text(),
        model_name,
        chunk_num,
        run,
    )

    # Write ratings JSON
    ratings_file.write_text(json.dumps(ratings, indent=2))

    # Call evaluate-chunk.py
    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "evaluate-chunk.py"),
         str(model_dir), str(run), str(ratings_file)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"  [WARN] evaluate-chunk.py failed: {result.stderr[:200]}", file=sys.stderr)

    total = sum(r["points"] for r in ratings.values())
    max_pts = len(ratings) * 2
    print(f"  [DONE] run{run}/chunk{chunk_num}: {total}/{max_pts} — {result.stdout.strip()}")
    return run, chunk_num, total, max_pts


def main():
    parser = argparse.ArgumentParser(description="Score knowledge eval with Opus")
    parser.add_argument("--model-dir", required=True, help="Path to model results dir (e.g. results/gemma4-4b)")
    parser.add_argument("--model-name", default="", help="Model name for ratings (default: inferred from dir name)")
    parser.add_argument("--runs", type=int, nargs="+", default=list(range(1, 6)), help="Runs to score (default: 1-5)")
    parser.add_argument("--chunks", type=int, nargs="+", default=list(range(1, 10)), help="Chunks to score (default: 1-9)")
    parser.add_argument("--parallel", type=int, default=9, help="Max parallel API calls (default: 9)")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        print("ERROR: ANTHROPIC_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    model_dir = Path(args.model_dir)
    if not model_dir.is_absolute():
        model_dir = SCRIPT_DIR / model_dir
    if not model_dir.exists():
        print(f"ERROR: model dir not found: {model_dir}", file=sys.stderr)
        sys.exit(1)

    model_name = args.model_name or model_dir.name

    print(f"Judging {model_name} ({len(args.runs)} runs × {len(args.chunks)} chunks = {len(args.runs)*len(args.chunks)} tasks)")
    print(f"Judge: {JUDGE_MODEL}, parallel: {args.parallel}")
    print()

    # Build task list
    tasks = [(run, chunk) for run in args.runs for chunk in args.chunks]

    # Score in parallel
    scores = {}  # (run, chunk) -> (total, max)
    with ThreadPoolExecutor(max_workers=args.parallel) as ex:
        futures = {
            ex.submit(judge_run_chunk, api_key, model_dir, model_name, run, chunk): (run, chunk)
            for run, chunk in tasks
        }
        for fut in as_completed(futures):
            try:
                _, _, total, max_pts = fut.result()
                run, chunk = futures[fut]
                scores[(run, chunk)] = (total, max_pts)
            except Exception as e:
                run, chunk = futures[fut]
                print(f"  [ERROR] run{run}/chunk{chunk}: {e}", file=sys.stderr)
                scores[(run, chunk)] = (0, 0)

    # Aggregate by run
    print()
    print("=" * 60)
    run_totals = {}
    for run in sorted(args.runs):
        run_total = sum(scores.get((run, c), (0, 0))[0] for c in args.chunks)
        run_max = sum(scores.get((run, c), (0, 0))[1] for c in args.chunks)
        run_totals[run] = (run_total, run_max)
        pct = 100 * run_total / run_max if run_max > 0 else 0
        print(f"  Run {run}: {run_total}/{run_max} ({pct:.1f}%)")

    all_pts = sum(v[0] for v in run_totals.values())
    all_max = sum(v[1] for v in run_totals.values())
    pct_all = 100 * all_pts / all_max if all_max > 0 else 0
    print(f"  TOTAL (all runs): {all_pts}/{all_max} ({pct_all:.1f}%)")
    if len(args.runs) > 1:
        per_run_avg = all_pts / len(args.runs)
        per_run_max = all_max / len(args.runs)
        print(f"  Per-run average:  {per_run_avg:.1f}/{per_run_max:.0f} ({100*per_run_avg/per_run_max:.1f}%)")
    print("=" * 60)


if __name__ == "__main__":
    main()
