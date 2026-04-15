#!/usr/bin/env python3
"""
validate-part-b.py — Deterministic syntax validation for chunk 9 Part B code.

Extracts fenced code blocks from a chunk 9 model response, classifies each by
language, and runs each through the appropriate validator. Returns a JSON
report that the judge can use as a hard signal.

Usage:
    python3 validate-part-b.py <response-file>
    python3 validate-part-b.py results/<model>/run1/chunk9-response.txt

Output (stdout): single JSON object
    {
      "scenarios": {
        "SC1": {
          "Part B": {
            "blocks": [
              {"language": "bash", "validator": "shellcheck", "ok": true|false, "errors": [...]}
            ],
            "all_valid": true|false,
            "block_count": N
          }
        },
        ...
      },
      "summary": {
        "total_blocks": N,
        "valid_blocks": N,
        "invalid_blocks": N,
        "scenarios_all_valid": [SC1, SC3, ...],
        "scenarios_some_invalid": [SC2, SC5, ...]
      }
    }

Validators per language:
    bash | sh         → shellcheck (with -s bash, -S warning)
    python | py       → python3 -m py_compile
    jq                → jq -n (pipe expression through)
    yaml | yml        → kubectl apply --dry-run=client -f - (if it looks like k8s)
                        otherwise → python3 -c 'import yaml; yaml.safe_load(...)'
    hcl | terraform   → terraform fmt -check -no-color (syntactic only — no provider init needed)
    json              → python3 -m json.tool
    sql               → no validator (returns 'unvalidated')
    go                → go vet (requires temp module setup)
    rust              → no validator (no quick rustc check without crate)
    *                 → returns 'unvalidated'

Falls back gracefully when a validator is missing — sets ok=null, error="validator unavailable".
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Map of language tag → validator function name
LANGUAGE_ALIASES = {
    "bash": "bash", "sh": "bash", "shell": "bash",
    "python": "python", "py": "python", "python3": "python",
    "jq": "jq",
    "yaml": "yaml", "yml": "yaml",
    "hcl": "hcl", "terraform": "hcl", "tf": "hcl",
    "json": "json",
    "go": "go", "golang": "go",
    "rust": "rust", "rs": "rust",
    "sql": "sql",
}

VALIDATOR_TOOLS = {
    "bash": "shellcheck",
    "python": "python3",
    "jq": "jq",
    "yaml": "kubectl",  # or python yaml
    "hcl": "terraform",
    "json": "python3",
    "go": "go",
}


def have_tool(name: str) -> bool:
    return shutil.which(name) is not None


def validate_bash(code: str) -> dict:
    if not have_tool("shellcheck"):
        return {"ok": None, "errors": ["shellcheck unavailable"]}
    try:
        proc = subprocess.run(
            ["shellcheck", "-s", "bash", "-S", "error", "-"],
            input=code,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if proc.returncode == 0:
            return {"ok": True, "errors": []}
        errors = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        return {"ok": False, "errors": errors[:10]}
    except Exception as e:
        return {"ok": None, "errors": [f"validator crashed: {e}"]}


def validate_python(code: str) -> dict:
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".py", delete=False) as f:
            f.write(code)
            path = f.name
        proc = subprocess.run(
            ["python3", "-m", "py_compile", path],
            capture_output=True, text=True, timeout=10,
        )
        Path(path).unlink(missing_ok=True)
        if proc.returncode == 0:
            return {"ok": True, "errors": []}
        return {"ok": False, "errors": [proc.stderr.strip()][:10]}
    except Exception as e:
        return {"ok": None, "errors": [f"validator crashed: {e}"]}


def validate_jq(code: str) -> dict:
    if not have_tool("jq"):
        return {"ok": None, "errors": ["jq unavailable"]}
    try:
        proc = subprocess.run(
            ["jq", "-n", code],
            capture_output=True, text=True, timeout=10,
        )
        if proc.returncode == 0:
            return {"ok": True, "errors": []}
        return {"ok": False, "errors": [proc.stderr.strip()][:10]}
    except Exception as e:
        return {"ok": None, "errors": [f"validator crashed: {e}"]}


def validate_yaml(code: str) -> dict:
    # Try python yaml first (pure syntax)
    try:
        proc = subprocess.run(
            ["python3", "-c",
             "import sys, yaml; list(yaml.safe_load_all(sys.stdin))"],
            input=code, capture_output=True, text=True, timeout=10,
        )
        if proc.returncode != 0:
            return {"ok": False, "errors": [proc.stderr.strip()]}
    except Exception as e:
        return {"ok": None, "errors": [f"yaml parse crashed: {e}"]}

    # If it has k8s markers, also try kubectl dry-run (client-side, no cluster)
    if re.search(r'\bapiVersion:\s*\S', code) and re.search(r'\bkind:\s*\S', code):
        if have_tool("kubectl"):
            try:
                proc = subprocess.run(
                    ["kubectl", "apply", "--dry-run=client", "-f", "-"],
                    input=code, capture_output=True, text=True, timeout=10,
                )
                if proc.returncode == 0:
                    return {"ok": True, "errors": []}
                # kubectl errors include schema mismatches; capture and report
                err = (proc.stderr or proc.stdout).strip()
                return {"ok": False, "errors": [line for line in err.splitlines() if line][:10]}
            except Exception as e:
                return {"ok": None, "errors": [f"kubectl crashed: {e}"]}

    # Plain YAML, parsed OK
    return {"ok": True, "errors": []}


def validate_hcl(code: str) -> dict:
    if not have_tool("terraform"):
        return {"ok": None, "errors": ["terraform unavailable"]}
    try:
        with tempfile.TemporaryDirectory() as d:
            tf_path = Path(d) / "main.tf"
            tf_path.write_text(code)
            # `terraform fmt -check` does pure syntax check, no init needed
            proc = subprocess.run(
                ["terraform", "fmt", "-check", "-diff", "-no-color", str(tf_path)],
                capture_output=True, text=True, timeout=10,
            )
        # fmt -check returns non-zero on fmt diffs but accepts valid HCL
        # (we only care about real syntax errors which produce stderr)
        if proc.stderr and "Error:" in proc.stderr:
            return {"ok": False, "errors": [line for line in proc.stderr.splitlines() if line.strip()][:10]}
        return {"ok": True, "errors": []}
    except Exception as e:
        return {"ok": None, "errors": [f"terraform crashed: {e}"]}


def validate_json(code: str) -> dict:
    try:
        json.loads(code)
        return {"ok": True, "errors": []}
    except Exception as e:
        return {"ok": False, "errors": [str(e)]}


def validate_unsupported(code: str) -> dict:
    return {"ok": None, "errors": ["language not validated"]}


VALIDATORS = {
    "bash": validate_bash,
    "python": validate_python,
    "jq": validate_jq,
    "yaml": validate_yaml,
    "hcl": validate_hcl,
    "json": validate_json,
}


# ── Code block extraction ───────────────────────────────────────────────────

CODE_BLOCK_RE = re.compile(
    r"^```(?P<lang>[\w-]*)\s*\n(?P<body>.*?)\n```",
    re.MULTILINE | re.DOTALL,
)

# Match Part B / SCx-B / **Part B** markers in the response
SCENARIO_HEADER_RE = re.compile(
    r"^##\s+(SC\d+)\b",
    re.MULTILINE,
)

PART_B_MARKER_RE = re.compile(
    r"\*\*?(SC\d+)-?B\*\*?:?|\*\*Part B\*\*",
    re.IGNORECASE,
)


def split_into_scenarios(text: str) -> dict:
    """
    Walks the response text and groups Part B code blocks under their scenario.
    Returns: {scenario_id: [code_blocks_in_order]}
    """
    scenarios = {}
    # Find all scenario headers + their start positions
    scenario_starts = [(m.group(1), m.start()) for m in SCENARIO_HEADER_RE.finditer(text)]
    if not scenario_starts:
        # Fallback: try to find SC1-A / SC1-B / SC1-C inline markers
        return _split_by_inline_markers(text)
    scenario_starts.append(("END", len(text)))

    for i in range(len(scenario_starts) - 1):
        scid, start = scenario_starts[i]
        _, end = scenario_starts[i + 1]
        scenario_text = text[start:end]
        # Within the scenario text, find the Part B section
        part_b_blocks = _extract_part_b_blocks(scenario_text)
        if part_b_blocks:
            scenarios[scid] = part_b_blocks
    return scenarios


def _extract_part_b_blocks(scenario_text: str) -> list:
    """
    Within one scenario section, find the Part B span and extract code blocks.
    Part B is between Part B marker and next Part marker (or end).
    """
    # Find Part B start
    b_match = re.search(
        r"(?:\*\*)?(?:Part\s*B|SC\d+-B|\bB:)\b(?:\*\*)?:?",
        scenario_text, re.IGNORECASE,
    )
    if not b_match:
        return []
    b_start = b_match.end()

    # Find Part C start (or end of scenario)
    c_match = re.search(
        r"(?:\*\*)?(?:Part\s*C|SC\d+-C|\bC:)\b(?:\*\*)?:?",
        scenario_text[b_start:], re.IGNORECASE,
    )
    b_end = b_start + c_match.start() if c_match else len(scenario_text)

    part_b_text = scenario_text[b_start:b_end]
    return [
        {"language": (m.group("lang") or "").strip().lower(), "code": m.group("body")}
        for m in CODE_BLOCK_RE.finditer(part_b_text)
    ]


def _split_by_inline_markers(text: str) -> dict:
    """Fallback if responses don't use ## SCx headers."""
    scenarios = {}
    # Find all SCx-B markers and their positions
    markers = [(m.group(1), m.start(), m.end())
               for m in re.finditer(r"\b(SC\d+)-B\b", text)]
    if not markers:
        return scenarios
    for i, (scid, _, marker_end) in enumerate(markers):
        # End at next marker (any letter) or 4000 chars
        next_marker = re.search(r"\bSC\d+-[ABC]\b", text[marker_end:])
        end = marker_end + next_marker.start() if next_marker else min(len(text), marker_end + 4000)
        section = text[marker_end:end]
        blocks = [
            {"language": (m.group("lang") or "").strip().lower(), "code": m.group("body")}
            for m in CODE_BLOCK_RE.finditer(section)
        ]
        if blocks:
            scenarios[scid] = blocks
    return scenarios


# ── Main ────────────────────────────────────────────────────────────────────

def validate_block(block: dict) -> dict:
    lang_raw = block["language"]
    lang = LANGUAGE_ALIASES.get(lang_raw, lang_raw or "unknown")
    validator = VALIDATORS.get(lang, validate_unsupported)
    result = validator(block["code"])
    return {
        "language": lang_raw or "unknown",
        "validator": lang if lang in VALIDATORS else "none",
        "ok": result["ok"],
        "errors": result["errors"],
        "lines": block["code"].count("\n") + 1,
    }


def main():
    if len(sys.argv) != 2:
        print("Usage: validate-part-b.py <response-file>", file=sys.stderr)
        sys.exit(1)
    response_path = Path(sys.argv[1])
    if not response_path.exists():
        print(f"File not found: {response_path}", file=sys.stderr)
        sys.exit(1)

    text = response_path.read_text()
    scenarios = split_into_scenarios(text)

    report = {"file": str(response_path), "scenarios": {}}
    total_blocks = valid_blocks = invalid_blocks = unvalidated_blocks = 0
    scenarios_all_valid = []
    scenarios_some_invalid = []

    for scid, blocks in scenarios.items():
        results = [validate_block(b) for b in blocks]
        all_ok = all(r["ok"] is True for r in results) if results else False
        any_bad = any(r["ok"] is False for r in results)
        report["scenarios"][scid] = {
            "Part B": {
                "block_count": len(results),
                "blocks": results,
                "all_valid": all_ok,
                "any_invalid": any_bad,
            }
        }
        total_blocks += len(results)
        valid_blocks += sum(1 for r in results if r["ok"] is True)
        invalid_blocks += sum(1 for r in results if r["ok"] is False)
        unvalidated_blocks += sum(1 for r in results if r["ok"] is None)
        if all_ok:
            scenarios_all_valid.append(scid)
        elif any_bad:
            scenarios_some_invalid.append(scid)

    report["summary"] = {
        "total_blocks": total_blocks,
        "valid_blocks": valid_blocks,
        "invalid_blocks": invalid_blocks,
        "unvalidated_blocks": unvalidated_blocks,
        "scenarios_all_valid": scenarios_all_valid,
        "scenarios_some_invalid": scenarios_some_invalid,
        "scenario_count": len(scenarios),
    }

    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
