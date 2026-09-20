#!/usr/bin/env python3
"""Run the ds4-eval case suites against an OpenAI-compatible endpoint.

Prompts and grading follow antirez/ds4's ds4-eval, so the numbers mean the same
thing. Nothing here is judged by a model: every case has a key and a
deterministic comparison, which is the point — no judge noise, no judge cost.

  ./run.py --url http://192.168.2.173:30000 --model glm5.3-flash \
           --suite core --out results/glm5.3-flash-q2kxl/core
"""
import argparse
import json
import os
import sys
import time
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import grade  # noqa: E402

SYSTEM_PROMPT = ("You are solving a hard benchmark question. Reason carefully. "
                 "The final answer must follow the requested format exactly.")


def system_prompt() -> str:
    """ds4's system prompt plus a per-request nonce.

    Without it every case sends a byte-identical system prompt, llama-server
    picks a slot by longest-common-prefix similarity and restores that slot's KV
    state. The server logs the moment it happens:

        selected slot by LCP similarity, f_sim_best = 1.000 (> 0.100 thold)

    The restore has a corner case that corrupts generation. Measured on
    GPQA Diamond/recoiTJPGUmzAkief: 128 s and 1610 tokens sent on its own,
    against 58000+ tokens and still running after 75 minutes as the fourth case
    of a run — same prompt, same sampling, same token budget.

    run-chunk-validated.sh has carried this nonce for the knowledge suite since
    2026-04. This runner was written without it.
    """
    return f"SESSION={uuid.uuid4()}\n{SYSTEM_PROMPT}"

# ds4-eval's own default. A per-case budget from the hard suite overrides it,
# which is also ds4's precedence when --max-tokens is not given explicitly.
#
# It is far too low for a reasoning model, and the failure is silent: the model
# spends the whole budget thinking, never writes an "Answer:" line, and scores
# zero exactly like a wrong answer. Measured on GLM-5.3-Flash — 9 of 10 failures
# in the first 41 cases were this, each one gx10 logging
# "eval time = 507521.26 ms / 16000 tokens". Pass --max-tokens explicitly, and
# raise --timeout with it or the client gives up before the budget does.
DEFAULT_MAX_TOKENS = 16000

# The trailing instruction is what makes grading deterministic; it is quoted
# from ds4_eval.c's build_question_prompt so a score is comparable to ds4's.
TAIL = {
    "choice": ("\nSolve the question. At the end, write exactly one final line in this "
               "format and do not write anything after it:\nAnswer: <letter>"),
    "line_set": ("\nAt the end, write exactly one final line in this format and do not "
                 "write anything after it:\n"
                 "Answer: <line number or comma-separated line numbers>"),
    "integer": ("\nSolve the problem. At the end, write exactly one final line in this "
                "format and do not write anything after it:\nAnswer: <integer>"),
    "rational": ("\nSolve the problem. Reduce the result. At the end, write exactly one "
                 "final line in this format and do not write anything after it:\n"
                 "Answer: <integer or reduced fraction>"),
    "ordered_sequence": ("\nSolve the problem. At the end, write exactly one final line "
                         "containing the answers in the requested order, separated by "
                         "commas, and do not write anything after it:\n"
                         "Answer: <ordered answers>"),
    "exact_text": ("\nSolve the problem. At the end, write exactly one final line in this "
                   "format and do not write anything after it:\nAnswer: <exact answer>"),
}


def build_prompt(case: dict) -> str:
    kind = grade.resolve_kind(case)
    text = case["question"] + "\n"
    if kind == "choice":
        text += "\nChoices:\n"
        for i, c in enumerate(case["choice"]):
            text += f"{chr(ord('A') + i)}. {c}\n"
    return text + TAIL.get(kind, TAIL["exact_text"])


def ask(url: str, model: str, key: str, prompt: str, max_tokens: int,
        temperature: float, timeout: int) -> dict:
    body = json.dumps({
        "model": model,
        "messages": [{"role": "system", "content": system_prompt()},
                     {"role": "user", "content": prompt}],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }).encode()
    headers = {"Content-Type": "application/json"}
    if key and key != "none":
        headers["Authorization"] = f"Bearer {key}"
    req = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions",
                                 data=body, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def summarise(records, args, blob, started, t0) -> dict:
    correct = sum(r["correct"] for r in records)
    by_source = {}
    for r in records:
        s = by_source.setdefault(r["source"], {"n": 0, "ok": 0})
        s["n"] += 1
        s["ok"] += r["correct"]
    return {
        "model": args.model, "endpoint": args.url, "suite": args.suite,
        "cases_rev": blob["rev"], "cases_repo": blob["repo"],
        "temperature": args.temperature, "max_tokens": args.max_tokens,
        "started": started.isoformat(),
        "finished": datetime.now(timezone.utc).isoformat(),
        "wall_seconds": round(time.time() - t0),
        "total": len(records), "correct": correct,
        "percentage": round(100 * correct / len(records), 2) if records else 0.0,
        "errors": sum(1 for r in records if r["error"]),
        "truncated": sum(1 for r in records if r["finish_reason"] == "length"),
        "by_source": {k: {**v, "pct": round(100 * v["ok"] / v["n"], 1)}
                      for k, v in sorted(by_source.items())},
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True, help="base URL, without /v1")
    ap.add_argument("--model", required=True)
    ap.add_argument("--api-key", default=os.environ.get("LLAMA_API_KEY", "none"))
    ap.add_argument("--cases", default=str(Path(__file__).parent / "cases.json"))
    ap.add_argument("--suite", default="core",
                    choices=["core", "hard", "hard-smoke", "all"])
    ap.add_argument("--source", help="only cases from this source, e.g. 'GPQA Diamond'")
    ap.add_argument("--limit", type=int, help="first N cases (smoke runs)")
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--max-tokens", type=int, default=0,
                    help="override the per-case budget from the suite")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--out", required=True, help="directory for results.json")
    args = ap.parse_args()

    blob = json.loads(Path(args.cases).read_text())
    cases = blob["cases"]
    if args.suite != "all":
        cases = [c for c in cases if args.suite in c["suites"]]
    if args.source:
        cases = [c for c in cases if c["source"] == args.source]
    if args.limit:
        cases = cases[:args.limit]
    if not cases:
        print("no cases selected", file=sys.stderr)
        return 1

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc)
    print(f"ds4-eval  suite={args.suite}  cases={len(cases)}  model={args.model}")
    print(f"  cases rev {blob['rev'][:12]} from {blob['repo']}")

    records, errors = [], 0
    t0 = time.time()

    def persist():
        # After every case, not just at the end. A long suite against a reasoning
        # model runs for hours, and an interruption used to lose all of it —
        # twice. Partial results are worth keeping; the summary says how many
        # cases they cover.
        (outdir / "results.json").write_text(json.dumps(
            {"summary": summarise(records, args, blob, started, t0),
             "cases": records}, indent=1, ensure_ascii=False))

    for i, case in enumerate(cases, 1):
        budget = args.max_tokens or case.get("max_tokens") or DEFAULT_MAX_TOKENS
        label = f"{case['source']}/{case['id']}"
        t = time.time()
        try:
            resp = ask(args.url, args.model, args.api_key, build_prompt(case),
                       budget, args.temperature, args.timeout)
            msg = resp["choices"][0]["message"]
            content = msg.get("content") or ""
            reasoning = msg.get("reasoning_content") or ""
            finish = resp["choices"][0].get("finish_reason")
            err = None
        except (urllib.error.URLError, OSError, KeyError, ValueError) as e:
            content = reasoning = ""
            finish = None
            err = f"{type(e).__name__}: {e}"
            errors += 1

        # Grade the visible answer. llama.cpp already splits reasoning out, so
        # content holds what ds4 would see after </think>.
        g = grade.grade(case, content)
        elapsed = time.time() - t
        records.append({
            "source": case["source"], "id": case["id"], "domain": case.get("domain"),
            "kind": g["kind"], "expected": g["expected"], "got": g["got"],
            "correct": g["correct"] and err is None,
            "finish_reason": finish, "seconds": round(elapsed, 1),
            "reasoning_chars": len(reasoning), "content_chars": len(content),
            "error": err, "response": content,
        })
        mark = "ok " if records[-1]["correct"] else ("ERR" if err else "x  ")
        print(f"  [{i:>3}/{len(cases)}] {mark} {label:<34} "
              f"{g['got']!r} vs {g['expected']!r}  {elapsed:.0f}s", flush=True)
        persist()

    summary = summarise(records, args, blob, started, t0)
    correct, truncated = summary["correct"], summary["truncated"]
    persist()
    (outdir / "run-config.txt").write_text(
        f"ds4-eval suite={args.suite} cases_rev={blob['rev']}\n"
        f"endpoint={args.url} model={args.model} temperature={args.temperature}\n"
        f"command={' '.join(sys.argv)}\n"
        f"date={started.isoformat()}\n")

    print(f"\n{correct}/{len(records)} = {summary['percentage']}%"
          f"   errors={errors} truncated={truncated}"
          f"   {summary['wall_seconds']}s")
    if truncated:
        # A truncated generation has no "Answer:" line, so it scores zero. On a
        # thinking model that is a budget problem, not a wrong answer: the hard
        # suite's per-case budget is 4096, which GLM-5.3-Flash can spend entirely
        # on reasoning. Do not compare a run with truncations against one without.
        print(f"  WARNING: {truncated} of {len(records)} generations hit the token "
              f"limit and scored zero.\n"
              f"  Re-run with --max-tokens 16000 (or higher) before using this number.")
    for s, v in summary["by_source"].items():
        print(f"  {s:<26} {v['ok']:>3}/{v['n']:<3} {v['pct']:>5.1f}%")
    print(f"-> {outdir}/results.json")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
