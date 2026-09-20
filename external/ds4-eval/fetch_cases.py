#!/usr/bin/env python3
"""Fetch the ds4-eval case tables from antirez/ds4 at a pinned revision and
emit them as JSON.

The cases live as C designated-initialiser tables in two files: the 92-case
`core` suite in ds4_eval.c and the 50-case `hard` suite in ds4_eval_cases.c.
We parse the C rather than vendoring the JSON so the answer keys never land in
this repo — committing them would put benchmark answers somewhere they can be
scraped into a future model's training set, which is the contamination the
suites exist to avoid.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_REV = "0aaea5a238fb41a35106a551e73c8409dfb751ac"
REPO = "antirez/ds4"
# Table -> the suite its entries belong to when they set no .suites bits of
# their own. The core table omits the field entirely; the hard table sets it.
SOURCES = {
    "ds4_eval.c": ("eval_core_cases", "core"),
    "ds4_eval_cases.c": ("eval_hard_cases", "hard"),
}
SUITE_BITS = {
    "EVAL_SUITE_CORE": "core",
    "EVAL_SUITE_HARD": "hard",
    "EVAL_SUITE_HARD_SMOKE": "hard-smoke",
}
KINDS = {
    "EVAL_ANSWER_AUTO": "auto",
    "EVAL_ANSWER_CHOICE": "choice",
    "EVAL_ANSWER_INTEGER": "integer",
    "EVAL_ANSWER_RATIONAL": "rational",
    "EVAL_ANSWER_EXACT_TEXT": "exact_text",
    "EVAL_ANSWER_ORDERED_SEQUENCE": "ordered_sequence",
    "EVAL_ANSWER_LINE_SET": "line_set",
}

_C_ESCAPES = {
    "n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"',
    "'": "'", "0": "\0", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
}


def fetch(rev: str, path: str) -> str:
    out = subprocess.run(
        ["gh", "api", f"repos/{REPO}/contents/{path}?ref={rev}", "--jq", ".content"],
        capture_output=True, text=True, check=True,
    ).stdout
    import base64
    return base64.b64decode(out).decode("utf-8", errors="surrogateescape")


def unescape_c(raw: str) -> str:
    """Decode one C string literal body. Octal escapes carry UTF-8 bytes, so
    they are collected as bytes and decoded together."""
    out = bytearray()
    i = 0
    while i < len(raw):
        c = raw[i]
        if c != "\\":
            out.extend(c.encode("utf-8"))
            i += 1
            continue
        i += 1
        if i >= len(raw):
            break
        e = raw[i]
        if e in "01234567":
            digits = ""
            while i < len(raw) and raw[i] in "01234567" and len(digits) < 3:
                digits += raw[i]
                i += 1
            out.append(int(digits, 8))
            continue
        if e == "x":
            i += 1
            digits = ""
            while i < len(raw) and raw[i] in "0123456789abcdefABCDEF":
                digits += raw[i]
                i += 1
            out.append(int(digits, 16))
            continue
        out.extend(_C_ESCAPES.get(e, e).encode("utf-8"))
        i += 1
    return out.decode("utf-8", errors="replace")


def split_top_level(body: str):
    """Yield each `{...}` element of an initialiser list, skipping braces that
    sit inside string literals."""
    depth = 0
    start = None
    in_str = False
    esc = False
    for i, c in enumerate(body):
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            if depth == 0:
                start = i + 1
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start is not None:
                yield body[start:i]
                start = None


def extract_table(text: str, name: str) -> str:
    m = re.search(rf"\b{re.escape(name)}\s*\[\s*\]\s*=\s*\{{", text)
    if not m:
        raise SystemExit(f"table {name} not found")
    start = m.end() - 1
    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(text)):
        c = text[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    raise SystemExit(f"table {name} is not closed")


_FIELD = re.compile(r"\.(\w+)\s*(?:\[\s*(\d+)\s*\])?\s*=\s*")
_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"', re.S)


def parse_case(block: str, default_suite: str) -> dict:
    case = {"choice": [], "alias": []}
    pos = 0
    while True:
        m = _FIELD.search(block, pos)
        if not m:
            break
        field, idx = m.group(1), m.group(2)
        pos = m.end()
        # A value is either a run of adjacent string literals or a bare
        # expression up to the next comma at this level.
        if block[pos:pos + 1] == '"':
            parts = []
            while True:
                s = _STRING.match(block, pos)
                if not s:
                    break
                parts.append(unescape_c(s.group(1)))
                pos = s.end()
                while pos < len(block) and block[pos] in " \t\r\n":
                    pos += 1
            value = "".join(parts)
        else:
            end = block.find(",", pos)
            if end == -1:
                end = len(block)
            value = block[pos:end].strip()
            pos = end
        if field in ("choice", "alias"):
            lst = case[field]
            i = int(idx) if idx is not None else len(lst)
            while len(lst) <= i:
                lst.append(None)
            lst[i] = value
        else:
            case[field] = value
    case["choice"] = [c for c in case["choice"] if c]
    case["alias"] = [a for a in case["alias"] if a]
    case["answer_kind"] = KINDS.get(case.get("answer_kind", "").strip(), "auto")
    suites = []
    for token, name in SUITE_BITS.items():
        if token in case.get("suites", ""):
            suites.append(name)
    case["suites"] = suites or [default_suite]
    mt = case.get("max_tokens")
    case["max_tokens"] = int(mt) if mt and mt.isdigit() else None
    return case


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rev", default=DEFAULT_REV,
                    help="antirez/ds4 commit to read the tables from")
    ap.add_argument("--out", default="cases.json")
    args = ap.parse_args()

    cases = []
    for path, (table, default_suite) in SOURCES.items():
        text = fetch(args.rev, path)
        for block in split_top_level(extract_table(text, table)):
            c = parse_case(block, default_suite)
            if not c.get("question"):
                continue
            cases.append(c)

    if not cases:
        print("no cases parsed", file=sys.stderr)
        return 1

    Path(args.out).write_text(json.dumps(
        {"rev": args.rev, "repo": REPO, "cases": cases}, indent=1, ensure_ascii=False))

    by_suite = {}
    by_source = {}
    for c in cases:
        for s in c["suites"]:
            by_suite[s] = by_suite.get(s, 0) + 1
        by_source[c["source"]] = by_source.get(c["source"], 0) + 1
    print(f"{len(cases)} cases -> {args.out}  (rev {args.rev[:12]})")
    print("  suites: " + ", ".join(f"{k}={v}" for k, v in sorted(by_suite.items())))
    print("  sources: " + ", ".join(f"{k}={v}" for k, v in sorted(by_source.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
