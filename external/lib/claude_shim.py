#!/usr/bin/env python3
"""An OpenAI-compatible endpoint in front of `claude -p`.

Lets the unchanged runners — ds4-eval, the knowledge suite, loop detection — put
a Claude model through the same cases as a local llama-server, as a reference
line. It uses the Claude Code login on this machine, so it needs no API key.

    ./claude_shim.py --model claude-opus-5 --effort high --port 8765
    ../ds4-eval/run.py --url http://127.0.0.1:8765 --model claude-opus-5 ...

What it can and cannot stand in for:
  - Tool calling is prompted, not native: the request's tools are described in
    the system prompt, the model writes its calls in a fenced block, and the
    shim returns them as OpenAI tool_calls. That is what a chat template does
    for a local model too, but this format is not the one the model was
    trained on, so a score is a lower bound. BFCL fc mode and tau2 run.
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
import re
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ARGS = None
WORKDIR = None
EMPTY_MCP = None


TOOL_BLOCK = re.compile(r"```tool_calls\s*(\[.*?\])\s*```", re.S)

TOOL_INSTRUCTIONS = """\
# Tools

You can call the functions below. To call one or more, end your reply with
exactly one fenced block of this form, and put nothing after it:

```tool_calls
[{"name": "<function name>", "arguments": {<arguments as a JSON object>}}]
```

Call several functions in one block when they are independent. When no function
fits the request, or you have what you need, answer in plain text instead and
write no block. Never invent a function or an argument that is not listed.

{tools}
"""


def tool_section(tools: list) -> str:
    listed = []
    for t in tools:
        f = t.get("function", t)
        listed.append(json.dumps({"name": f.get("name"), "description": f.get("description", ""),
                                  "parameters": f.get("parameters", {})}, ensure_ascii=False))
    return TOOL_INSTRUCTIONS.replace("{tools}", "\n".join(listed))


def text_of(m: dict) -> str:
    c = m.get("content")
    if isinstance(c, list):
        c = "".join(x.get("text", "") for x in c if isinstance(x, dict))
    return c or ""


def render_turn(m: dict) -> str:
    role = m["role"]
    if role == "tool":
        return f"[Result of tool call {m.get('tool_call_id') or m.get('name') or ''}]\n{text_of(m)}"
    if role == "assistant":
        text = text_of(m)
        calls = m.get("tool_calls") or []
        if calls:
            block = json.dumps([{"name": c["function"]["name"],
                                 "arguments": json.loads(c["function"]["arguments"] or "{}")}
                                for c in calls], ensure_ascii=False)
            text = (text + "\n\n" if text else "") + f"```tool_calls\n{block}\n```"
        return f"[Your earlier reply]\n{text}"
    return f"[Earlier message from the user]\n{text_of(m)}"


def render(messages: list, tools: list | None = None) -> tuple[str, str]:
    """Split OpenAI messages into a system prompt and one user prompt. A
    multi-turn exchange is flattened into a labelled transcript, since the CLI
    takes a single prompt. Tool results and earlier tool calls are part of it."""
    system = "\n\n".join(text_of(m) for m in messages if m["role"] == "system")
    if tools:
        system = (system + "\n\n" if system else "") + tool_section(tools)
    turns = [m for m in messages if m["role"] != "system"]
    if len(turns) == 1 and turns[0]["role"] == "user":
        return system, text_of(turns[0])
    parts = [render_turn(m) for m in turns[:-1]]
    last = turns[-1]
    if last["role"] == "user":
        parts.append(f"[Current message from the user]\n{text_of(last)}")
    else:
        parts.append(render_turn(last))
        parts.append("[Continue from here]")
    return system, "\n\n".join(parts)


def parse_tool_calls(text: str) -> tuple[str, list]:
    """Split the model's reply into plain content and OpenAI tool_calls. A block
    that is not a JSON list of {name, arguments} objects is left in the text."""
    m = TOOL_BLOCK.search(text)
    if not m:
        return text, []
    try:
        calls = json.loads(m.group(1))
        assert isinstance(calls, list) and all(isinstance(c, dict) and "name" in c for c in calls)
    except (ValueError, AssertionError):
        return text, []
    content = (text[:m.start()] + text[m.end():]).strip()
    return content, [{"id": f"call_{i}", "type": "function",
                      "function": {"name": c["name"],
                                   "arguments": json.dumps(c.get("arguments") or {}, ensure_ascii=False)}}
                     for i, c in enumerate(calls)]


def call_claude(system: str, prompt: str) -> dict:
    # Nothing from the request reaches the command line: the system prompt goes
    # through a file this process names itself, the user prompt through stdin.
    # The argv is built only from this server's own startup arguments.
    with tempfile.NamedTemporaryFile("w", dir=WORKDIR, prefix="system-", suffix=".txt",
                                     delete=False) as f:
        f.write(system or "You are a helpful assistant.")
        system_file = f.name
    cmd = ["claude", "-p", "--model", ARGS.model, "--effort", ARGS.effort,
           "--system-prompt-file", system_file,
           "--tools", "", "--strict-mcp-config", "--mcp-config", str(EMPTY_MCP),
           "--setting-sources", "", "--output-format", "json",
           "--no-session-persistence"]
    t0 = time.time()
    try:
        proc = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                              cwd=WORKDIR, timeout=ARGS.timeout)
    finally:
        Path(system_file).unlink(missing_ok=True)
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
        tools = payload.get("tools") or []
        system, prompt = render(payload.get("messages", []), tools)
        try:
            r = call_claude(system, prompt)
        except (RuntimeError, subprocess.TimeoutExpired, OSError) as e:
            print(f"  ERROR {e}", file=sys.stderr, flush=True)
            return self._json(500, {"error": {"message": str(e)}})
        content, calls = parse_tool_calls(r["text"]) if tools else (r["text"], [])
        finish = "tool_calls" if calls else "stop"
        print(f"  {r['completion_tokens']:>6} tok  {r['seconds']:>6.1f}s"
              f"{'  ' + str(len(calls)) + ' tool call(s)' if calls else ''}", file=sys.stderr, flush=True)
        usage = {"prompt_tokens": r["prompt_tokens"], "completion_tokens": r["completion_tokens"],
                 "total_tokens": r["prompt_tokens"] + r["completion_tokens"]}
        message = {"role": "assistant", "content": content if content or not calls else None}
        if calls:
            message["tool_calls"] = calls
        if payload.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            delta = {"role": "assistant", "content": message["content"]}
            if calls:
                delta["tool_calls"] = [{"index": i, **c} for i, c in enumerate(calls)]
            for chunk in (
                {"choices": [{"index": 0, "delta": delta, "finish_reason": None}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": finish}]},
                {"choices": [], "usage": usage},
            ):
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
            self.wfile.write(b"data: [DONE]\n\n")
        else:
            self._json(200, {"id": "shim", "object": "chat.completion", "model": ARGS.model,
                             "choices": [{"index": 0, "finish_reason": finish, "message": message}],
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
