#!/usr/bin/env python3
"""
Agentic evaluation harness.

Runs a task against a model by:
1. Setting up the environment (running the setup script)
2. Sending the goal to the model with tool definitions
3. Executing tool calls and feeding results back
4. Enforcing limits (time, step count, loop detection)
5. Running verification
6. Outputting results as JSON

Usage:
    python3 harness.py --model-url http://192.168.2.171:8001 --model-name qwen3.5-9b --task AG1
    python3 harness.py --model-url http://192.168.2.171:8001 --model-name qwen3.5-9b --tier 1
"""

import argparse
import json
import os
import subprocess
import sys
import time
import yaml
import re
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
TASKS_DIR = SCRIPT_DIR / "tasks"
RESULTS_DIR = SCRIPT_DIR / "results"

SYSTEM_PROMPT = """You are an expert systems administrator and developer. You have access to a Linux shell via the exec tool. Use it to complete the task given to you.

Rules:
- Execute commands to accomplish the goal
- Verify your work before reporting completion
- If a command fails, read the error and adapt your approach
- Do NOT explain what you plan to do — just do it
- When done, call exec one final time with the command: echo "TASK_COMPLETE"
"""

TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "exec",
            "description": "Execute a shell command and return its output. Use this for all file operations, system commands, and verification.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The bash command to execute"
                    }
                },
                "required": ["command"]
            }
        }
    }
]


def load_task(task_id: str) -> dict:
    """Load a task definition from YAML."""
    path = TASKS_DIR / f"{task_id}.yaml"
    if not path.exists():
        print(f"Task {task_id} not found at {path}", file=sys.stderr)
        sys.exit(1)
    with open(path) as f:
        return yaml.safe_load(f)


def _shell(command: str, timeout: int = 30, ssh_target: str = None) -> subprocess.CompletedProcess:
    """Run a shell command locally or via SSH."""
    if ssh_target:
        # Escape single quotes in command for SSH
        escaped = command.replace("'", "'\\''")
        cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5",
               ssh_target, f"bash -c '{escaped}'"]
    else:
        cmd = ["bash", "-c", command]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


# Module-level SSH target (set by --exec-host)
_ssh_target = None


def run_setup(task: dict) -> bool:
    """Run the task's setup script."""
    setup = task.get("setup", "")
    if not setup:
        return True
    result = _shell(setup, timeout=30, ssh_target=_ssh_target)
    if result.returncode != 0:
        print(f"Setup failed: {result.stderr}", file=sys.stderr)
        return False
    return True


def run_verify(task: dict) -> bool:
    """Run the task's verification script."""
    verify = task.get("verify", "")
    if not verify:
        return True
    result = _shell(verify, timeout=10, ssh_target=_ssh_target)
    return result.returncode == 0


def exec_command(command: str, timeout: int = 30) -> str:
    """Execute a shell command and return output."""
    try:
        result = _shell(command, timeout=timeout, ssh_target=_ssh_target)
        output = result.stdout
        if result.stderr:
            output += f"\nSTDERR: {result.stderr}"
        if result.returncode != 0:
            output += f"\n(exit code: {result.returncode})"
        return output.strip() or "(no output)"
    except subprocess.TimeoutExpired:
        return f"ERROR: Command timed out after {timeout}s"
    except Exception as e:
        return f"ERROR: {e}"


def call_model(url: str, api_key: str, model: str, messages: list,
               tools: list = None, max_tokens: int = 4096) -> dict:
    """Call the model API and return the response."""
    import urllib.request

    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 0.1,
    }
    if tools:
        payload["tools"] = tools
        payload["tool_choice"] = "auto"

    data = json.dumps(payload).encode()
    headers = {
        "Content-Type": "application/json",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    req = urllib.request.Request(
        f"{url}/v1/chat/completions",
        data=data,
        headers=headers,
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
            # Clean control characters
            raw = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', raw)
            return json.loads(raw)
    except Exception as e:
        return {"error": str(e)}


def run_task(task: dict, model_url: str, model_name: str, api_key: str,
             verbose: bool = False) -> dict:
    """Run a single task and return results."""
    task_id = task["id"]
    max_steps = task.get("max_steps", 30)
    time_limit = task.get("time_limit", 300)

    # Setup
    if not run_setup(task):
        return {"task_id": task_id, "title": task.get("title", ""), "tier": task.get("tier", 0), "status": "setup_failed", "verified": False, "steps": 0, "elapsed_seconds": 0, "loops_detected": 0, "score": {"completion": 0, "efficiency": 0, "recovery": 0, "quality": 0, "total": 0, "max": 10}, "steps_log": []}

    # Build initial messages
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task["goal"]}
    ]

    # Tracking
    steps = []
    step_count = 0
    identical_calls = {}
    start_time = time.time()
    completed = False
    gave_up = False

    while step_count < max_steps:
        elapsed = time.time() - start_time
        if elapsed > time_limit:
            if verbose:
                print(f"  [TIMEOUT after {elapsed:.0f}s]")
            break

        # Call model
        response = call_model(model_url, api_key, model_name, messages,
                             tools=TOOL_DEFINITIONS)

        if "error" in response:
            if verbose:
                print(f"  [API ERROR: {response['error']}]")
            steps.append({"type": "api_error", "error": response["error"]})
            break

        choice = response.get("choices", [{}])[0]
        message = choice.get("message", {})
        finish_reason = choice.get("finish_reason", "")

        # Check for tool calls
        tool_calls = message.get("tool_calls", [])

        if not tool_calls:
            # Model responded with text, no more tool calls
            content = message.get("content", "") or message.get("reasoning_content", "")
            if verbose:
                print(f"  [TEXT]: {content[:100]}...")
            steps.append({"type": "text", "content": content})

            if "TASK_COMPLETE" in content:
                completed = True
            break

        # Add assistant message to history
        messages.append(message)

        # Execute each tool call
        for tc in tool_calls:
            step_count += 1
            func = tc.get("function", {})
            tool_name = func.get("name", "")
            args = json.loads(func.get("arguments", "{}"))
            command = args.get("command", "")

            if verbose:
                print(f"  [{step_count}/{max_steps}] exec: {command[:80]}")

            # Loop detection
            call_key = f"{tool_name}:{command}"
            identical_calls[call_key] = identical_calls.get(call_key, 0) + 1
            if identical_calls[call_key] >= 3:
                if verbose:
                    print(f"  [LOOP DETECTED: {command[:50]}]")
                steps.append({
                    "type": "loop_detected",
                    "command": command,
                    "count": identical_calls[call_key]
                })
                # Force stop
                step_count = max_steps
                break

            # Execute
            if "TASK_COMPLETE" in command:
                completed = True
                output = "Task marked as complete."
            else:
                output = exec_command(command)

            steps.append({
                "type": "tool_call",
                "step": step_count,
                "command": command,
                "output": output[:2000],  # Truncate long outputs
                "elapsed": time.time() - start_time
            })

            # Add tool result to messages
            messages.append({
                "role": "tool",
                "tool_call_id": tc.get("id", f"call_{step_count}"),
                "content": output[:2000]
            })

    # Verify
    elapsed = time.time() - start_time
    verified = run_verify(task)

    # Score
    loop_count = sum(1 for v in identical_calls.values() if v >= 2)
    min_steps = task.get("min_steps", 2)

    completion_score = 4 if verified else (2 if completed else 0)
    efficiency_score = 2 if step_count <= min_steps * 2 else (1 if step_count <= min_steps * 3 else 0)
    recovery_score = 2 if loop_count == 0 else (1 if loop_count == 1 else 0)
    quality_score = 2 if verified and not any(s.get("type") == "loop_detected" for s in steps) else (1 if verified else 0)

    total_score = completion_score + efficiency_score + recovery_score + quality_score

    return {
        "task_id": task_id,
        "title": task.get("title", ""),
        "tier": task.get("tier", 0),
        "model": model_name,
        "status": "verified" if verified else ("completed" if completed else "failed"),
        "verified": verified,
        "steps": step_count,
        "min_steps": min_steps,
        "max_steps": max_steps,
        "elapsed_seconds": round(elapsed, 1),
        "time_limit": time_limit,
        "loops_detected": loop_count,
        "score": {
            "completion": completion_score,
            "efficiency": efficiency_score,
            "recovery": recovery_score,
            "quality": quality_score,
            "total": total_score,
            "max": 10
        },
        "steps_log": steps,
        "timestamp": datetime.now().isoformat()
    }


def main():
    parser = argparse.ArgumentParser(description="Agentic evaluation harness")
    parser.add_argument("--model-url", required=True, help="Model API base URL")
    parser.add_argument("--model-name", required=True, help="Model name for API calls")
    parser.add_argument("--api-key", default="", help="API key (reads from env LLAMA_API_KEY if not set)")
    parser.add_argument("--task", help="Single task ID (e.g., AG1)")
    parser.add_argument("--tier", type=int, help="Run all tasks in a tier (1, 2, or 3)")
    parser.add_argument("--all", action="store_true", help="Run all tasks")
    parser.add_argument("--exec-host", help="SSH target for running commands (e.g., ubuntu@192.168.2.171). If not set, runs locally.")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show step-by-step output")
    parser.add_argument("--output", "-o", help="Output JSON file (default: results/<model>/<task>.json)")
    args = parser.parse_args()

    api_key = args.api_key or os.environ.get("LLAMA_API_KEY", "")

    # Set global SSH target for exec commands
    global _ssh_target
    _ssh_target = args.exec_host

    # Collect tasks to run
    tasks = []
    if args.task:
        tasks.append(load_task(args.task))
    elif args.tier:
        for f in sorted(TASKS_DIR.glob("AG*.yaml"), key=lambda p: int(p.stem[2:])):
            t = yaml.safe_load(f.read_text())
            if t.get("tier") == args.tier:
                tasks.append(t)
    elif args.all:
        for f in sorted(TASKS_DIR.glob("AG*.yaml"), key=lambda p: int(p.stem[2:])):
            tasks.append(yaml.safe_load(f.read_text()))
    else:
        parser.error("Specify --task, --tier, or --all")

    # Run tasks
    results = []
    total_score = 0
    max_score = 0

    for task in tasks:
        task_id = task["id"]
        print(f"\n{'='*60}")
        print(f"  {task_id}: {task.get('title', '')}")
        print(f"  Tier {task.get('tier')}, {task.get('time_limit')}s limit, {task.get('max_steps')} max steps")
        print(f"{'='*60}")

        result = run_task(task, args.model_url, args.model_name, api_key,
                         verbose=args.verbose)
        results.append(result)

        score = result["score"]
        total_score += score["total"]
        max_score += score["max"]

        status_icon = "PASS" if result["verified"] else "FAIL"
        print(f"  [{status_icon}] {score['total']}/{score['max']} pts "
              f"({result['steps']} steps, {result['elapsed_seconds']}s)")

    # Summary
    print(f"\n{'='*60}")
    print(f"  TOTAL: {total_score}/{max_score} ({100*total_score/max_score:.1f}%)")
    print(f"  Tasks: {sum(1 for r in results if r['verified'])}/{len(results)} verified")
    print(f"{'='*60}")

    # Save results
    output_dir = RESULTS_DIR / args.model_name
    output_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    output_file = args.output or str(output_dir / f"agentic-{timestamp}.json")

    summary = {
        "model": args.model_name,
        "model_url": args.model_url,
        "timestamp": datetime.now().isoformat(),
        "total_score": total_score,
        "max_score": max_score,
        "percentage": round(100 * total_score / max_score, 1) if max_score > 0 else 0,
        "tasks_verified": sum(1 for r in results if r["verified"]),
        "tasks_total": len(results),
        "results": results
    }

    with open(output_file, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"\nResults saved to {output_file}")


if __name__ == "__main__":
    main()
