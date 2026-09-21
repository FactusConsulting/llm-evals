#!/usr/bin/env python3
"""An OpenAI-compatible endpoint in front of `claude -p`.

Lets the unchanged runners — ds4-eval, the knowledge suite, loop detection — put
a Claude model through the same cases as a local llama-server, as a reference
line. It uses the Claude Code login on this machine, so it needs no API key.

    ./claude_shim.py --model claude-opus-5 --effort high --port 8765
    ../ds4-eval/run.py --url http://127.0.0.1:8765 --model claude-opus-5 ...

What it can and cannot stand in for:
  - Text in, text out. There is no native tool calling, so BFCL's fc mode and
    tau2 cannot run through it; those need a real Anthropic API endpoint.
  - temperature, top_p, seed and max_tokens are accepted and ignored — the CLI
    exposes none of them. Two "seeds" are two independent samples, nothing more.
  - usage.completion_tokens is the API's output_tokens, which includes thinking.

Every call runs with no tools, no MCP servers, no user or project settings and an
explicit system prompt, from an empty directory. Left at its defaults the CLI
attaches the whole tool and connector catalogue: measured here, 86469 input
tokens for a one-line question against 453 with it stripped.
"""
import argparse
import json
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ARGS = None
WORKDIR = None
EMPTY_MCP = None


def render(messages: list) -> tuple[str, str]:
    """Split OpenAI messages into a system prompt and one user prompt. A
    multi-turn exchange is flattened into a labelled transcript, since the CLI
    takes a single prompt."""
    system = "\n\n".join(m["content"] for m in messages if m["role"] == "system")
    turns = [m for m in messages if m["role"] != "system"]
    if len(turns) == 1:
        return system, turns[0]["content"]
    parts = []
    for m in turns[:-1]:
        label = "Your earlier reply" if m["role"] == "assistant" else "Earlier message from the user"
        parts.append(f"[{label}]\n{m['content']}")
    parts.append(f"[Current message from the user]\n{turns[-1]['content']}")
    return system, "\n\n".join(parts)


def call_claude(system: str, prompt: str) -> dict:
    cmd = ["claude", "-p", "--model", ARGS.model, "--effort", ARGS.effort,
           "--system-prompt", system or "You are a helpful assistant.",
           "--tools", "", "--strict-mcp-config", "--mcp-config", str(EMPTY_MCP),
           "--setting-sources", "", "--output-format", "json",
           "--no-session-persistence"]
    t0 = time.time()
    proc = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                          cwd=WORKDIR, timeout=ARGS.timeout)
    out = proc.stdout
    try:
        data = json.loads(out[out.index("{"):])
    except ValueError:
        raise RuntimeError(f"claude -p returned no JSON (exit {proc.returncode}): "
                           f"{(proc.stderr or out)[:300]}")
    if data.get("is_error"):
        raise RuntimeError(f"claude -p error: {str(data.get('result'))[:300]}")
    usage = data.get("usage") or {}
    return {
        "text": data.get("result") or "",
        "prompt_tokens": (usage.get("input_tokens") or 0)
                         + (usage.get("cache_read_input_tokens") or 0)
                         + (usage.get("cache_creation_input_tokens") or 0),
        "completion_tokens": usage.get("output_tokens") or 0,
        "seconds": round(time.time() - t0, 1),
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *a):
        pass

    def _json(self, code: int, obj) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            self._json(200, {"object": "list", "data": [{"id": ARGS.model, "object": "model"}]})
        elif self.path == "/props":
            self._json(200, {"build_info": f"claude -p ({ARGS.model}, effort {ARGS.effort})",
                             "default_generation_settings": {"n_ctx": None}})
        elif self.path == "/slots":
            self._json(200, [])
        elif self.path == "/health":
            self._json(200, {"status": "ok"})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        if not self.path.endswith("/chat/completions"):
            return self._json(404, {"error": "not found"})
        payload = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        system, prompt = render(payload.get("messages", []))
        try:
            r = call_claude(system, prompt)
        except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
            print(f"  ERROR {e}", file=sys.stderr, flush=True)
            return self._json(500, {"error": {"message": str(e)}})
        print(f"  {r['completion_tokens']:>6} tok  {r['seconds']:>6.1f}s", file=sys.stderr, flush=True)
        usage = {"prompt_tokens": r["prompt_tokens"], "completion_tokens": r["completion_tokens"],
                 "total_tokens": r["prompt_tokens"] + r["completion_tokens"]}
        if payload.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for chunk in (
                {"choices": [{"index": 0, "delta": {"role": "assistant", "content": r["text"]},
                              "finish_reason": None}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]},
                {"choices": [], "usage": usage},
            ):
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            self.wfile.write(b"data: [DONE]\n\n")
        else:
            self._json(200, {"id": "shim", "object": "chat.completion", "model": ARGS.model,
                             "choices": [{"index": 0, "finish_reason": "stop",
                                          "message": {"role": "assistant", "content": r["text"]}}],
                             "usage": usage})


def main() -> int:
    global ARGS, WORKDIR, EMPTY_MCP
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="claude-opus-5")
    ap.add_argument("--effort", default="high", choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--timeout", type=int, default=3600, help="seconds one claude -p call may take")
    ARGS = ap.parse_args()
    WORKDIR = tempfile.mkdtemp(prefix="claude-shim-")
    EMPTY_MCP = Path(WORKDIR) / "empty-mcp.json"
    EMPTY_MCP.write_text('{"mcpServers":{}}')
    print(f"claude shim: {ARGS.model} effort={ARGS.effort} on http://127.0.0.1:{ARGS.port}", file=sys.stderr, flush=True)
    ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
