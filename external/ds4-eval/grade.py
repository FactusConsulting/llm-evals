#!/usr/bin/env python3
"""Deterministic grading for ds4-eval cases.

A port of the answer extraction and matching in antirez/ds4's ds4_eval.c, so a
score produced here means the same thing as one produced by `ds4-eval`. The
behaviours that are easy to get subtly wrong are covered by test_grade.py.

No model judges anything: every answer kind reduces to string equality after a
kind-specific normalisation.
"""
import re

EVAL_ANSWER_MAX = 256


def resolve_kind(case: dict) -> str:
    """ds4 leaves .answer_kind unset on the core table and derives it."""
    kind = case.get("answer_kind") or "auto"
    if kind != "auto":
        return kind
    if case.get("choice"):
        return "choice"
    if case.get("source") == "COMPSEC":
        return "line_set"
    return "integer"


def _is_letter_boundary(before: str, after: str) -> bool:
    return not (before.isalnum() or before == "_") and not (after.isalnum() or after == "_")


def visible_part(generated: str) -> str:
    """Everything after the last reasoning block is what gets graded."""
    i = generated.find("</think>")
    return generated[i + 8:] if i != -1 else generated


def find_last_answer_marker(visible: str):
    """Index of the last 'answer' that is followed by a colon; else the first
    'answer' anywhere."""
    last = None
    low = visible.lower()
    for m in re.finditer(r"answer", low):
        p = m.start()
        before = visible[p - 1] if p > 0 else " "
        after = visible[p + 6] if p + 6 < len(visible) else "\0"
        if not _is_letter_boundary(before, after):
            continue
        q = p + 6
        while q < len(visible) and visible[q].isspace():
            q += 1
        if q < len(visible) and visible[q] == ":":
            last = p
    if last is not None:
        return last
    m = re.search(r"answer", low)
    return m.start() if m else None


def answer_payload(line: str):
    """The text after 'Answer:' on a line, or None."""
    marker = find_last_answer_marker(line)
    if marker is None:
        return None
    p = marker + 6
    while p < len(line) and line[p].isspace():
        p += 1
    if p >= len(line) or line[p] != ":":
        return None
    p += 1
    while p < len(line) and (line[p].isspace() or line[p] == "*"):
        p += 1
    return line[p:]


_NEGATION = re.compile(r"\b(not|isn't|is not|rather than|instead of|rule out|"
                       r"ruled out|eliminate[sd]?|reject(?:ed|s)?|excludes?|"
                       r"excluding|never)\b", re.I)


def _letter_is_negated(segment: str) -> bool:
    """ds4 skips a letter that a same-line clause explicitly rejects, so
    'not B, ... D' picks D."""
    tail = segment[-64:]
    cut = max(tail.rfind(";"), tail.rfind(". "))
    if cut != -1:
        tail = tail[cut + 1:]
    return bool(_NEGATION.search(tail))


def find_answer_letter(generated: str, nchoices: int) -> str:
    if nchoices <= 0:
        return "?"
    visible = visible_part(generated)
    max_letter = chr(ord("A") + nchoices - 1)
    marker = find_last_answer_marker(visible)
    if marker is not None:
        region = visible[marker:marker + 96]
        for i, ch in enumerate(region):
            c = ch.upper()
            if not ("A" <= c <= max_letter):
                continue
            before = region[i - 1] if i > 0 else " "
            after = region[i + 1] if i + 1 < len(region) else "\0"
            if not _is_letter_boundary(before, after):
                continue
            # "I'll" and "A careful reading" are prose, not a pick.
            if after == "'":
                continue
            if after in " \t":
                w = i + 1
                while w < len(region) and region[w] in " \t":
                    w += 1
                if w < len(region) and region[w].islower():
                    continue
            if _letter_is_negated(region[:i]):
                continue
            return c
    # Reverse scan: the last standalone in-range capital anywhere.
    for i in range(len(visible) - 1, -1, -1):
        c = visible[i].upper()
        if "A" <= c <= max_letter:
            before = visible[i - 1] if i > 0 else " "
            after = visible[i + 1] if i + 1 < len(visible) else "\0"
            if _is_letter_boundary(before, after):
                return c
    return "?"


def normalize_integer(src: str) -> str:
    s = "".join(ch for ch in src if ch.isdigit() or ch in "-+")
    neg = s.startswith("-")
    digits = s.lstrip("+-")
    digits = digits.lstrip("0") or "0"
    return ("-" if neg and digits != "0" else "") + digits


def normalize_rational(src: str) -> str:
    s = "".join(ch for ch in src if ch.isdigit() or ch in "-+/.")
    return s.rstrip(".")


def normalize_exact(src: str) -> str:
    out = []
    i = 0
    while i < len(src):
        c = src[i]
        if c.isspace() or c in "$*{}":
            i += 1
            continue
        if c == "\\":
            for tok in ("\\boxed", "\\right", "\\left"):
                if src.startswith(tok, i):
                    i += len(tok)
                    break
            else:
                i += 1
            continue
        out.append(c.lower())
        i += 1
    return "".join(out).rstrip(".;")


def normalize_ordered(src: str) -> str:
    out = []
    in_tag = False
    for c in src:
        if c == "<":
            in_tag = True
            continue
        if in_tag:
            if c == ">":
                in_tag = False
            continue
        if c.isalnum() or c in ",-+/.":
            out.append(c.lower())
    return "".join(out).rstrip(".,")


def parse_line_spec(spec: str):
    """'12' or '12,15' or '12-14' -> set of line numbers, or None if unparsable."""
    if spec is None:
        return None
    nums = set()
    for part in re.split(r"[,\s]+", spec.strip()):
        if not part:
            continue
        m = re.fullmatch(r"(\d+)\s*-\s*(\d+)", part)
        if m:
            a, b = int(m.group(1)), int(m.group(2))
            if a > b or b > 255:
                return None
            nums.update(range(a, b + 1))
            continue
        if part.isdigit():
            n = int(part)
            if n > 255:
                return None
            nums.add(n)
            continue
        return None
    return nums or None


def compsec_matches(expected_spec: str, got_spec: str) -> bool:
    """Every line the model named must be inside the accepted set, and it must
    name at least one. The expected set may be a small audited range when
    adjacent lines are equivalent locations for the same bug."""
    expected = parse_line_spec(expected_spec)
    got = parse_line_spec(got_spec)
    if not expected or not got:
        return False
    return got.issubset(expected)


_NORMALIZERS = {
    "integer": normalize_integer,
    "rational": normalize_rational,
    "exact_text": normalize_exact,
    "ordered_sequence": normalize_ordered,
}


def extract(case: dict, generated: str) -> str:
    kind = resolve_kind(case)
    if kind == "choice":
        return find_answer_letter(generated, len(case.get("choice") or []))
    visible = visible_part(generated)
    payload = answer_payload(visible)
    if payload is None:
        return "?"
    if kind == "line_set":
        return payload.strip() or "?"
    norm = _NORMALIZERS.get(kind)
    got = norm(payload) if norm else payload.strip()
    return got or "?"


def matches(case: dict, got: str) -> bool:
    kind = resolve_kind(case)
    expected = case.get("answer")
    if not got or got == "?" or expected is None:
        return False
    if kind == "choice":
        return got[0] == expected[0]
    if kind == "line_set":
        return compsec_matches(expected, got)
    norm = _NORMALIZERS.get(kind, lambda s: s)
    for candidate in [expected] + list(case.get("alias") or []):
        if got == norm(candidate):
            return True
    return False


def grade(case: dict, generated: str) -> dict:
    got = extract(case, generated)
    return {"got": got, "expected": case.get("answer"),
            "kind": resolve_kind(case), "correct": matches(case, got)}
