#!/usr/bin/env python3
"""Run the ds4-eval case suites against an OpenAI-compatible endpoint.

Prompts and grading follow antirez/ds4's ds4-eval, so the numbers mean the same
thing. Nothing here is judged by a model: every case has a key and a
deterministic comparison, which is the point — no judge noise, no judge cost.

  ./run.py --url http://192.168.2.173:30000 --model glm5.3-flash \
           --suite core --mode gate --out results/glm5.3-flash-q2kxl/gate

Two named sampling presets (--mode gate|measure) trade off reproducibility
against honest variance; see README.md.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import grade  # noqa: E402

SYSTEM_PROMPT = ("You are solving a hard benchmark question. Reason carefully. "
                 "The final answer must follow the requested format exactly.")

# ds4-eval's own default. A per-case budget from the hard suite overrides it,
# which is also ds4's precedence when --max-tokens is not given explicitly.
#
# It is far too low for a reasoning model, and the failure is silent: the model
# spends the whole budget thinking, never writes an "Answer:" line, and scores
# zero exactly like a wrong answer. Pass --max-tokens explicitly, and raise
# --timeout with it or the client gives up before the budget does.
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

# --nonce fixed: a deterministic per-case token instead of a fresh uuid4 per
# request. llama-server picks a slot by longest-common-prefix similarity and
# restores that slot's KV state; a byte-identical system prompt across cases
# makes every request match whatever slot last ran, which has a corner case
# that corrupts generation. A random nonce avoids the collision but makes a
# run unreproducible — a different random prefix steers a temperature-0 model
# down a different reasoning path. The fixed nonce is unique per case (so no
# two cases share a slot) and stable across runs (so a run can be repeated).
MODE_PRESETS = {
    "gate": {"nonce": "fixed", "temperature": 0.0, "seed": 0},
    "measure": {"nonce": "fixed", "temperature": 1.0, "top_p": 1.0, "min_p": 0.05},
}
SAMPLING_DEFAULTS = {"nonce": "fixed", "temperature": 0.0, "top_p": None,
                     "min_p": None, "seed": None}

FORCE_INSTRUCTION = ("You have run out of budget. Based on your reasoning so far, "
                     "write exactly one final line in the required format and "
                     "nothing else.")
FORCE_MAX_TOKENS = 512
REASONING_KEEP_CHARS = 6000
PROGRESS_INTERVAL = 60


def resolve_sampling(args) -> dict:
    """Explicit flags win; an unset flag falls back to --mode's preset, then to
    SAMPLING_DEFAULTS. Both presets use a fixed nonce; only --nonce random
    overrides it."""
    preset = MODE_PRESETS.get(args.mode, {})
    out = {}
    for key, default in SAMPLING_DEFAULTS.items():
        explicit = getattr(args, key)
        if explicit is not None:
            out[key] = explicit
        elif key in preset:
            out[key] = preset[key]
        else:
            out[key] = default
    out["mode"] = args.mode
    return out


def fixed_session(case: dict) -> str:
    key = f"{case['source']}/{case['id']}"
    return hashlib.sha256(key.encode()).hexdigest()[:32]


def system_prompt(case: dict, nonce_mode: str) -> str:
    token = str(uuid.uuid4()) if nonce_mode == "random" else fixed_session(case)
    return f"SESSION={token}\n{SYSTEM_PROMPT}"


def build_prompt(case: dict) -> str:
    kind = grade.resolve_kind(case)
    text = case["question"] + "\n"
    if kind == "choice":
        text += "\nChoices:\n"
        for i, c in enumerate(case["choice"]):
            text += f"{chr(ord('A') + i)}. {c}\n"
    return text + TAIL.get(kind, TAIL["exact_text"])


def has_answer_line(text: str) -> bool:
    return re.search(r"(?i)answer\s*:", text) is not None


def repetition_stats(text: str) -> tuple:
    """Repeated-line and repeated-sentence counts, folded in from loopwatch.py.
    Lines/sentences of 40 characters or fewer are too short to be a loop."""
    lines = [l.strip() for l in text.splitlines() if len(l.strip()) > 40]
    sents = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text) if len(s.strip()) > 40]
    line_counts, sent_counts = Counter(lines), Counter(sents)
    repeated_lines = sum(v - 1 for v in line_counts.values() if v > 1)
    repeated_sentences = sum(v - 1 for v in sent_counts.values() if v > 1)
    return repeated_lines, repeated_sentences


def estimate_tokens(text: str) -> int:
    """Character-based fallback for an endpoint that omits usage. ~4 chars/token
    is a rough average across English and code; good enough to flag a missing
    number as roughly right, never used when real usage is available."""
    return max(1, round(len(text) / 4))


def phase_usage(usage, prompt_text: str, completion_text: str) -> tuple:
    if usage:
        return usage.get("prompt_tokens", 0), usage.get("completion_tokens", 0), False
    return estimate_tokens(prompt_text), estimate_tokens(completion_text), True


def request_body(model: str, messages: list, max_tokens: int, sampling: dict,
                  stream: bool = True) -> dict:
    body = {
        "model": model,
        "messages": messages,
        "temperature": sampling["temperature"],
        "max_tokens": max_tokens,
    }
    # top_p is a standard field; min_p and seed are llama.cpp extensions, sent
    # the same way in the same body.
    if sampling.get("top_p") is not None:
        body["top_p"] = sampling["top_p"]
    if sampling.get("min_p") is not None:
        body["min_p"] = sampling["min_p"]
    if sampling.get("seed") is not None:
        body["seed"] = sampling["seed"]
    if stream:
        body["stream"] = True
        body["stream_options"] = {"include_usage": True}
    return body


def _headers(key: str) -> dict:
    headers = {"Content-Type": "application/json"}
    if key and key != "none":
        headers["Authorization"] = f"Bearer {key}"
    return headers


def fetch_json(url: str, path: str, key: str, timeout: int = 10):
    """GET url+path as JSON. Never raises: a snapshot call that fails must not
    take the run down with it."""
    try:
        req = urllib.request.Request(url.rstrip("/") + path, headers=_headers(key))
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        return None


def server_snapshot(url: str, key: str) -> dict:
    """build_info, per-slot n_ctx, slot count and the first slot's sampler
    params — recorded once so a result set carries the config it was measured
    under. A failed call leaves its field null; the run continues either way."""
    props = fetch_json(url, "/props", key)
    slots = fetch_json(url, "/slots", key)
    n_ctx = n_slots = params = None
    if isinstance(slots, list):
        n_slots = len(slots)
        n_ctx = [s.get("n_ctx") for s in slots if isinstance(s, dict)]
        if slots and isinstance(slots[0], dict):
            params = slots[0].get("params")
    build_info = props.get("build_info") if isinstance(props, dict) else None
    return {"build_info": build_info, "n_slots": n_slots, "n_ctx": n_ctx, "params": params}


def post_stream(url: str, key: str, body: dict, timeout: int) -> dict:
    """POST a streamed chat completion and collect content, reasoning_content,
    finish_reason and usage from the SSE deltas. Prints a progress line about
    once a minute so a multi-hour case is not a silent wait."""
    data = json.dumps(body).encode()
    req = urllib.request.Request(url.rstrip("/") + "/v1/chat/completions",
                                 data=data, headers=_headers(key))
    content_parts, reasoning_parts = [], []
    finish_reason = None
    usage = None
    n_pieces = 0
    t0 = time.time()
    last_progress = t0
    with urllib.request.urlopen(req, timeout=timeout) as r:
        for raw in r:
            if not raw.startswith(b"data: "):
                continue
            payload = raw[6:].strip()
            if payload == b"[DONE]":
                break
            try:
                d = json.loads(payload)
            except ValueError:
                continue
            if d.get("usage"):
                usage = d["usage"]
            choices = d.get("choices") or []
            if choices:
                delta = choices[0].get("delta") or {}
                content_piece = delta.get("content")
                reasoning_piece = delta.get("reasoning_content")
                if content_piece:
                    content_parts.append(content_piece)
                    n_pieces += 1
                if reasoning_piece:
                    reasoning_parts.append(reasoning_piece)
                    n_pieces += 1
                fr = choices[0].get("finish_reason")
                if fr:
                    finish_reason = fr
            now = time.time()
            if now - last_progress > PROGRESS_INTERVAL:
                dl, ds = repetition_stats("".join(reasoning_parts))
                print(f"    ... {n_pieces} tokens so far, {dl + ds} repeats so far "
                      f"({now - t0:.0f}s)", flush=True)
                last_progress = now
    return {"content": "".join(content_parts), "reasoning": "".join(reasoning_parts),
            "finish_reason": finish_reason, "usage": usage, "elapsed": time.time() - t0}


def force_closure(url: str, model: str, key: str, sys_msg: str, user_msg: str,
                  reasoning: str, content: str, sampling: dict, timeout: int) -> dict:
    """One follow-up turn for a case that hit the token ceiling mid-reasoning
    with no Answer: line: the original exchange, the truncated reasoning as an
    assistant turn, and a request for exactly one final line."""
    tail = reasoning if reasoning else content
    if len(tail) > REASONING_KEEP_CHARS:
        tail = tail[-REASONING_KEEP_CHARS:]
    messages = [
        {"role": "system", "content": sys_msg},
        {"role": "user", "content": user_msg},
        {"role": "assistant", "content": tail},
        {"role": "user", "content": FORCE_INSTRUCTION},
    ]
    # Greedy, whatever phase 1 sampled with. This turn extracts a conclusion from
    # reasoning that already exists; sampling noise here adds variance to the
    # score without measuring anything about the model.
    greedy = {**sampling, "temperature": 0.0}
    body = request_body(model, messages, FORCE_MAX_TOKENS, greedy)
    return post_stream(url, key, body, timeout)


def write_results(outdir: Path, summary: dict, records: list) -> None:
    (outdir / "results.json").write_text(json.dumps(
        {"summary": summary, "cases": records}, indent=1, ensure_ascii=False))


def summarise(records, args, sampling, blob, started, t0, snapshot) -> dict:
    correct = sum(r["correct"] for r in records)
    by_source = {}
    for r in records:
        s = by_source.setdefault(r["source"], {"n": 0, "ok": 0})
        s["n"] += 1
        s["ok"] += r["correct"]
    return {
        "model": args.model, "endpoint": args.url, "suite": args.suite,
        "cases_rev": blob["rev"], "cases_repo": blob["repo"],
        "mode": sampling["mode"], "nonce": sampling["nonce"],
        "temperature": sampling["temperature"], "top_p": sampling["top_p"],
        "min_p": sampling["min_p"], "seed": sampling["seed"],
        "max_tokens": args.max_tokens, "think_budget": args.think_budget,
        "force": not args.no_force, "server": snapshot,
        "started": started.isoformat(),
        "finished": datetime.now(timezone.utc).isoformat(),
        "wall_seconds": round(time.time() - t0),
        "total": len(records), "correct": correct,
        "percentage": round(100 * correct / len(records), 2) if records else 0.0,
        "errors": sum(1 for r in records if r["error"]),
        "truncated": sum(1 for r in records if r["finish_reason"] == "length"),
        "forced": sum(1 for r in records if r.get("forced")),
        "by_source": {k: {**v, "pct": round(100 * v["ok"] / v["n"], 1)}
                      for k, v in sorted(by_source.items())},
    }


def execute(cases, args, sampling, blob, snapshot, outdir) -> tuple:
    """Run every case in order, persisting results.json after each one. Returns
    (records, summary)."""
    started = datetime.now(timezone.utc)
    print(f"ds4-eval  suite={args.suite}  cases={len(cases)}  model={args.model}  "
          f"mode={sampling['mode'] or 'custom'}")
    print(f"  cases rev {blob['rev'][:12]} from {blob['repo']}")
    print(f"  nonce={sampling['nonce']} temperature={sampling['temperature']} "
          f"top_p={sampling['top_p']} min_p={sampling['min_p']} seed={sampling['seed']}")

    records, errors = [], 0
    t0 = time.time()

    for i, case in enumerate(cases, 1):
        budget = args.max_tokens or case.get("max_tokens") or DEFAULT_MAX_TOKENS
        phase1_budget = args.think_budget or budget
        label = f"{case['source']}/{case['id']}"
        sys_msg = system_prompt(case, sampling["nonce"])
        user_msg = build_prompt(case)
        t = time.time()
        forced = False
        finish = None
        content = reasoning = ""
        err = None
        prompt_tokens = completion_tokens = None
        estimated = False
        try:
            body = request_body(args.model,
                                [{"role": "system", "content": sys_msg},
                                 {"role": "user", "content": user_msg}],
                                phase1_budget, sampling)
            r1 = post_stream(args.url, args.api_key, body, args.timeout)
            content, reasoning = r1["content"], r1["reasoning"]
            finish = r1["finish_reason"]
            prompt_tokens, completion_tokens, estimated = phase_usage(
                r1["usage"], sys_msg + user_msg, content + reasoning)

            if not args.no_force and finish == "length" and not has_answer_line(content):
                forced = True
                r2 = force_closure(args.url, args.model, args.api_key, sys_msg, user_msg,
                                   reasoning, content, sampling, args.timeout)
                content = r2["content"]
                finish = r2["finish_reason"] or finish
                _, extra_tokens, est2 = phase_usage(r2["usage"], "", r2["content"])
                completion_tokens += extra_tokens
                estimated = estimated or est2
        except (urllib.error.URLError, OSError, KeyError, ValueError) as e:
            err = f"{type(e).__name__}: {e}"
            errors += 1

        g = grade.grade(case, content)
        elapsed = time.time() - t
        repeated_lines, repeated_sentences = repetition_stats(reasoning)
        records.append({
            "source": case["source"], "id": case["id"], "domain": case.get("domain"),
            "kind": g["kind"], "expected": g["expected"], "got": g["got"],
            "correct": g["correct"] and err is None,
            "finish_reason": finish, "seconds": round(elapsed, 1),
            "reasoning_chars": len(reasoning), "content_chars": len(content),
            "prompt_tokens": prompt_tokens, "completion_tokens": completion_tokens,
            "estimated": estimated, "forced": forced,
            "repeated_lines": repeated_lines, "repeated_sentences": repeated_sentences,
            "error": err, "response": content,
        })
        mark = "ok " if records[-1]["correct"] else ("ERR" if err else "x  ")
        flag = " FORCED" if forced else ""
        print(f"  [{i:>3}/{len(cases)}] {mark} {label:<34} "
              f"{g['got']!r} vs {g['expected']!r}  {elapsed:.0f}s{flag}", flush=True)
        write_results(outdir, summarise(records, args, sampling, blob, started, t0, snapshot),
                      records)

    summary = summarise(records, args, sampling, blob, started, t0, snapshot)
    write_results(outdir, summary, records)
    return records, summary


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
    ap.add_argument("--mode", choices=["gate", "measure"],
                    help="gate: temp 0, fixed nonce, seed 0. measure: ds4's own "
                    "temp/top_p/min_p defaults, fixed nonce, seed from --seed. "
                    "An explicit --temperature/--top-p/--min-p/--seed/--nonce "
                    "overrides the preset.")
    ap.add_argument("--nonce", choices=["fixed", "random"],
                    help="fixed (default): sha256(source/id), stable and unique "
                    "per case. random: a fresh uuid4 per request.")
    ap.add_argument("--temperature", type=float)
    ap.add_argument("--top-p", dest="top_p", type=float)
    ap.add_argument("--min-p", dest="min_p", type=float)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--max-tokens", type=int, default=0,
                    help="override the per-case budget from the suite")
    ap.add_argument("--think-budget", type=int, default=0,
                    help="cap on the first phase's tokens, before any forced "
                    "closure; default is the resolved --max-tokens budget")
    ap.add_argument("--no-force", action="store_true",
                    help="disable the two-phase think-closure follow-up")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--out", required=True, help="directory for results.json")
    args = ap.parse_args()

    sampling = resolve_sampling(args)

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
    snapshot = server_snapshot(args.url, args.api_key)

    records, summary = execute(cases, args, sampling, blob, snapshot, outdir)
    correct, truncated, forced = summary["correct"], summary["truncated"], summary["forced"]
    errors = summary["errors"]
    (outdir / "run-config.txt").write_text(
        f"ds4-eval suite={args.suite} cases_rev={blob['rev']}\n"
        f"endpoint={args.url} model={args.model} mode={sampling['mode']}\n"
        f"nonce={sampling['nonce']} temperature={sampling['temperature']} "
        f"top_p={sampling['top_p']} min_p={sampling['min_p']} seed={sampling['seed']}\n"
        f"command={' '.join(sys.argv)}\n"
        f"date={summary['started']}\n")

    print(f"\n{correct}/{len(records)} = {summary['percentage']}%"
          f"   errors={errors} truncated={truncated} forced={forced}"
          f"   {summary['wall_seconds']}s")
    if truncated:
        # Still truncated after any forced closure attempt: the follow-up's own
        # 512 tokens were not enough either, or --no-force skipped it entirely.
        print(f"  WARNING: {truncated} of {len(records)} generations were still "
              f"truncated after any forced closure and scored zero.\n"
              f"  Re-run with a higher --max-tokens or --think-budget before "
              f"using this number.")
    for s, v in summary["by_source"].items():
        print(f"  {s:<26} {v['ok']:>3}/{v['n']:<3} {v['pct']:>5.1f}%")
    print(f"-> {outdir}/results.json")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
