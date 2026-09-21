#!/usr/bin/env python3
"""Tests for run.py against a local OpenAI-SSE mock server: no request in this
file ever reaches a real inference endpoint. Same procedural style as
test_grade.py — a flat list of (name, got, want) checks."""
import json
import shutil
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run  # noqa: E402

REQUEST_LOG = []  # (model, len(messages)) per POST this process has seen
TEMP_LOG = []     # the temperature each POST asked for, in order


def sse(*chunks) -> bytes:
    out = b"".join(b"data: " + json.dumps(c).encode() + b"\n\n" for c in chunks)
    return out + b"data: [DONE]\n\n"


def delta(**kw) -> dict:
    return {"choices": [{"delta": kw, "finish_reason": None}]}


def finish(reason: str) -> dict:
    return {"choices": [{"delta": {}, "finish_reason": reason}]}


def usage_chunk(prompt: int, completion: int) -> dict:
    return {"choices": [], "usage": {"prompt_tokens": prompt, "completion_tokens": completion}}


SCENARIOS = {
    "plain": sse(delta(content="Solving.\n"), delta(content="Answer: B"),
                finish("stop"), usage_chunk(12, 6)),
    "reasoning": sse(delta(reasoning_content="thinking it through\n"),
                     delta(content="Answer: 204"), finish("stop"), usage_chunk(30, 20)),
    "no-usage": sse(delta(content="Answer: A"), finish("stop")),
}
# "ceiling": the first call (2 messages) hits the token cap with no Answer:
# line; the forced follow-up (4 messages) answers cleanly.
CEILING_FIRST = sse(delta(reasoning_content="round and round " * 400), finish("length"),
                    usage_chunk(40, 4096))
CEILING_FORCED = sse(delta(content="Answer: 42"), finish("stop"), usage_chunk(4200, 8))


class MockHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # no keep-alive/chunking needed for a test double

    def log_message(self, *a):
        pass

    def _write(self, body: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(length) or b"{}")
        model = payload.get("model")
        messages = payload.get("messages", [])
        REQUEST_LOG.append((model, len(messages)))
        TEMP_LOG.append(payload.get("temperature"))
        if model == "ceiling":
            body = CEILING_FORCED if len(messages) >= 4 else CEILING_FIRST
        else:
            body = SCENARIOS.get(model, SCENARIOS["plain"])
        self._write(body, "text/event-stream")

    def do_GET(self):
        if self.path == "/props":
            self._write(json.dumps({"build_info": "b1234"}).encode(), "application/json")
        elif self.path == "/slots":
            self._write(json.dumps([{"n_ctx": 131072,
                                     "params": {"n_predict": -1, "samplers": ["top_p"]}}]
                                   ).encode(), "application/json")
        else:
            self.send_response(404)
            self.end_headers()


_server = HTTPServer(("127.0.0.1", 0), MockHandler)
threading.Thread(target=_server.serve_forever, daemon=True).start()
URL = f"http://127.0.0.1:{_server.server_port}"

TESTS = []
_tmp_dirs = []


def check(name, got, want):
    TESTS.append((name, got, want))


def make_case(source: str, cid: str, **extra) -> dict:
    case = {"source": source, "id": cid, "question": "q", "choice": ["x", "y"], "answer": "A"}
    case.update(extra)
    return case


def sampling_of(mode, **overrides):
    ns = SimpleNamespace(mode=mode, nonce=None, temperature=None, top_p=None,
                         min_p=None, seed=None, reasoning_budget=0)
    for k, v in overrides.items():
        setattr(ns, k, v)
    return run.resolve_sampling(ns)


def run_one(case: dict, model: str, sampling: dict, no_force: bool = False,
           think_budget: int = 0, max_tokens: int = 200):
    REQUEST_LOG.clear()
    TEMP_LOG.clear()
    args = SimpleNamespace(url=URL, model=model, api_key="none", timeout=10,
                           max_tokens=max_tokens, think_budget=think_budget,
                           reasoning_budget=0, no_force=no_force, suite="core")
    blob = {"rev": "0" * 40, "repo": "antirez/ds4"}
    outdir = Path(tempfile.mkdtemp(prefix="ds4-runner-v2-test-"))
    _tmp_dirs.append(outdir)
    records, summary = run.execute([case], args, sampling, blob, {"build_info": None}, outdir)
    return records[0], summary, outdir


# --- fixed nonce: stable across calls, unique per case ----------------------
c1, c2 = make_case("GPQA Diamond", "abc"), make_case("GPQA Diamond", "def")
check("fixed nonce is stable", run.fixed_session(c1), run.fixed_session(c1))
check("fixed nonce is unique per case", run.fixed_session(c1) != run.fixed_session(c2), True)
check("fixed nonce is 32 hex chars", len(run.fixed_session(c1)), 32)
check("random nonce varies per call",
      run.system_prompt(c1, "random") != run.system_prompt(c1, "random"), True)

# --- modes set the right sampling fields -------------------------------------
gate = sampling_of("gate")
check("gate temperature", gate["temperature"], 0.0)
check("gate nonce", gate["nonce"], "fixed")
check("gate seed", gate["seed"], 0)
check("gate leaves top_p unset", gate["top_p"], None)

measure = sampling_of("measure", seed=3)
check("measure temperature", measure["temperature"], 1.0)
check("measure top_p", measure["top_p"], 1.0)
check("measure min_p", measure["min_p"], 0.05)
check("measure seed is passed through from --seed", measure["seed"], 3)

override = sampling_of("measure", temperature=0.7)
check("an explicit flag overrides the mode preset", override["temperature"], 0.7)

measure_body = run.request_body("m", [{"role": "user", "content": "x"}], 100, measure)
check("min_p reaches the request body", measure_body["min_p"], 0.05)
check("top_p reaches the request body", measure_body["top_p"], 1.0)
check("seed reaches the request body", measure_body["seed"], 3)
check("stream is requested", measure_body["stream"], True)
check("usage is requested with the stream",
      measure_body["stream_options"], {"include_usage": True})

served = sampling_of("served", seed=2)
served_body = run.request_body("m", [], 100, served)
check("served mode sends no temperature", "temperature" in served_body, False)
check("served mode sends no top_p or min_p",
      ("top_p" in served_body, "min_p" in served_body), (False, False))
check("served mode still carries the seed", served_body.get("seed"), 2)
check("served mode keeps the fixed nonce", served["nonce"], "fixed")

gate_body = run.request_body("m", [], 100, gate)
check("gate body omits top_p entirely", "top_p" in gate_body, False)
check("gate body carries seed 0", gate_body["seed"], 0)

# --- repetition stats, folded in from loopwatch.py ---------------------------
line = "This exact forty-plus character line repeats three times."
dl, ds = run.repetition_stats("\n".join([line, line, line]))
check("repeated line counted (n-1 per repeat)", dl, 2)
short_dl, _ = run.repetition_stats("short\nlines\n")
check("lines of 40 chars or fewer are not counted", short_dl, 0)

# --- has_answer_line ----------------------------------------------------------
check("answer line is detected", run.has_answer_line("reasoning...\nAnswer: B"), True)
check("no answer line", run.has_answer_line("reasoning without a verdict"), False)

# --- integration: usage accounting -------------------------------------------
plain_case = make_case("GPQA Diamond", "p1", answer="B")
rec, summ, outdir1 = run_one(plain_case, "plain", gate)
check("plain case graded correct", rec["correct"], True)
check("plain case not forced", rec["forced"], False)
check("usage tokens taken from the stream, not estimated",
      (rec["prompt_tokens"], rec["completion_tokens"], rec["estimated"]), (12, 6, False))
check("results.json exists after the run", (outdir1 / "results.json").exists(), True)

reasoning_case = make_case("AIME2025", "p2", choice=[], answer_kind="integer", answer="204")
rec2, _, _ = run_one(reasoning_case, "reasoning", gate)
check("reasoning_content graded via content alone", rec2["got"], "204")
check("reasoning_content is captured separately", rec2["reasoning_chars"] > 0, True)

no_usage_case = make_case("GPQA Diamond", "p3")
rec3, _, _ = run_one(no_usage_case, "no-usage", gate)
check("missing usage falls back to a character estimate", rec3["estimated"], True)
check("estimated completion tokens are positive", rec3["completion_tokens"] > 0, True)

# --- integration: think-closure --------------------------------------------
ceiling_case = make_case("AIME2025", "p4", choice=[], answer_kind="integer", answer="42")
rec4, summ4, _ = run_one(ceiling_case, "ceiling", gate)
log_after_forced = list(REQUEST_LOG)  # snapshot: REQUEST_LOG itself keeps mutating
check("length-with-no-answer triggers exactly one follow-up",
      log_after_forced, [("ceiling", 2), ("ceiling", 4)])
check("the case is marked forced", rec4["forced"], True)
check("grading uses the forced answer", rec4["got"], "42")
check("summary counts the forced case", summ4["forced"], 1)

rec5, _, _ = run_one(ceiling_case, "ceiling", gate, no_force=True)
log_after_no_force = list(REQUEST_LOG)
check("--no-force skips the follow-up", log_after_no_force, [("ceiling", 2)])
check("without forcing the case scores wrong", rec5["correct"], False)

# The follow-up extracts a conclusion from reasoning that already exists, so it
# is greedy even when phase 1 sampled at the model's recipe temperature.
run_one(ceiling_case, "ceiling", measure)
check("measure mode: phase 1 samples, the forced turn is greedy",
      list(TEMP_LOG), [1.0, 0.0])

ok_case = make_case("GPQA Diamond", "p5", answer="B")  # finish_reason stop, has an answer
rec6, _, _ = run_one(ok_case, "plain", gate)
check("a clean stop never triggers a follow-up", rec6["forced"], False)

# --- results.json is written after every case, not just at the end ---------
seen_sizes = []
_orig_write_results = run.write_results


def _spy(outdir, summary, records):
    seen_sizes.append(len(records))
    _orig_write_results(outdir, summary, records)


run.write_results = _spy
multi_cases = [make_case("GPQA Diamond", "m1"), make_case("GPQA Diamond", "m2"),
              make_case("GPQA Diamond", "m3")]
multi_args = SimpleNamespace(url=URL, model="plain", api_key="none", timeout=10,
                             max_tokens=200, think_budget=0, reasoning_budget=0,
                             no_force=False, suite="core")
multi_outdir = Path(tempfile.mkdtemp(prefix="ds4-runner-v2-test-multi-"))
_tmp_dirs.append(multi_outdir)
run.execute(multi_cases, multi_args, gate, {"rev": "0" * 40, "repo": "antirez/ds4"},
           {"build_info": None}, multi_outdir)
run.write_results = _orig_write_results
check("results.json is persisted after each case (final size repeats once)",
      seen_sizes, [1, 2, 3, 3])

# --- server snapshot never raises, even against a real endpoint shape ------
snap = run.server_snapshot(URL, "none")
check("snapshot reads build_info", snap["build_info"], "b1234")
check("snapshot reads slot count", snap["n_slots"], 1)
check("snapshot reads n_ctx per slot", snap["n_ctx"], [131072])
bad_snap = run.server_snapshot("http://127.0.0.1:1", "none")  # nothing listens here
check("a failed snapshot call yields null fields, not an exception",
      bad_snap, {"build_info": None, "n_slots": None, "n_ctx": None, "params": None})

budget_body = run.request_body("m", [], 100, {"reasoning_budget": 65536})
check("a reasoning budget is sent as llama-server's two fields",
      (budget_body.get("reasoning_budget_tokens"), budget_body.get("reasoning_budget_message")),
      (65536, run.BUDGET_MESSAGE))
check("no reasoning budget sends neither field",
      [k for k in run.request_body("m", [], 100, {"reasoning_budget": 0}) if "budget" in k], [])

run.RETRY_PAUSE = 0
dead_args = SimpleNamespace(url="http://127.0.0.1:9", model="plain", api_key="none", timeout=2,
                            max_tokens=200, think_budget=0, reasoning_budget=0,
                            no_force=False, suite="core")
dead_outdir = Path(tempfile.mkdtemp(prefix="ds4-runner-v2-test-dead-"))
_tmp_dirs.append(dead_outdir)
dead_records, dead_summary = run.execute([make_case("GPQA Diamond", "d1")], dead_args, gate,
                                         {"rev": "0" * 40, "repo": "antirez/ds4"},
                                         {"build_info": None}, dead_outdir)
check("a dropped connection is retried before the case is given up",
      (dead_records[0]["retries"], bool(dead_records[0]["error"]), dead_summary["errors"]),
      (run.RETRIES, True, 1))


def main() -> int:
    failed = 0
    for name, got, want in TESTS:
        if got != want:
            print(f"FAIL {name}: got {got!r}, want {want!r}")
            failed += 1
    print(f"{len(TESTS) - failed}/{len(TESTS)} passed")
    _server.shutdown()
    for d in _tmp_dirs:
        shutil.rmtree(d, ignore_errors=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
