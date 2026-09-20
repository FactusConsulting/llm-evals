#!/usr/bin/env python3
"""Tests for the ds4_eval.c grading port. Each case here is a behaviour the C
implementation spells out explicitly, so a regression shows up as a named
failure rather than a drifted score."""
import sys

import grade

MC4 = {"source": "GPQA Diamond", "choice": ["w", "x", "y", "z"], "answer": "B"}
MC10 = {"source": "MMLU-Pro", "choice": list("abcdefghij"), "answer": "J",
        "answer_kind": "choice"}
INT = {"source": "AIME2025", "answer": "204"}
SEC = {"source": "COMPSEC", "answer": "41-43"}
EXACT = {"source": "OlympiadBench", "answer": "\\frac{1}{2}",
         "answer_kind": "exact_text", "alias": ["0.5"]}
RAT = {"source": "OlympiadBench", "answer": "3/4", "answer_kind": "rational"}
SEQ = {"source": "LiveBench", "answer": "a,b,c", "answer_kind": "ordered_sequence"}

TESTS = []


def check(name, got, want):
    TESTS.append((name, got, want))


# --- kind resolution (the core table sets no answer_kind) -------------------
check("auto choice", grade.resolve_kind(MC4), "choice")
check("auto compsec", grade.resolve_kind(SEC), "line_set")
check("auto integer", grade.resolve_kind(INT), "integer")

# --- reasoning is stripped before grading ----------------------------------
check("think stripped",
      grade.extract(MC4, "I think D is wrong</think>\nAnswer: B"), "B")
check("no think tag", grade.extract(MC4, "Answer: B"), "B")

# --- the LAST 'Answer:' wins -----------------------------------------------
check("last marker wins",
      grade.extract(MC4, "Answer: A\nno wait\nAnswer: C"), "C")

# --- prose that must not be read as a pick ---------------------------------
check("prose word skipped", grade.extract(MC4, "Answer: A careful look gives B"), "B")
check("contraction skipped", grade.extract(MC4, "Answer: I'll say C"), "C")
check("negated distractor", grade.extract(MC4, "Answer: not B, so D"), "D")

# --- out-of-range letters are not choices ----------------------------------
check("letter beyond nchoices", grade.extract(MC4, "Answer: Z"), "?")
check("ten choices reach J", grade.extract(MC10, "Answer: J"), "J")

# --- integers --------------------------------------------------------------
check("integer plain", grade.extract(INT, "Answer: 204"), "204")
check("integer leading zeros", grade.extract(INT, "Answer: 0204"), "204")
check("integer with commas", grade.extract(INT, "Answer: 1,024"), "1024")
check("integer bold marker", grade.extract(INT, "**Answer:** 204"), "204")

# --- exact text ------------------------------------------------------------
# ds4 drops the backslash itself and keeps the command name, so \frac{1}{2}
# normalises to "frac12" — not "\frac12".
check("exact latex stripped", grade.extract(EXACT, "Answer: \\boxed{\\frac{1}{2}}"),
      "frac12")
check("exact matches", grade.matches(EXACT, grade.extract(EXACT, "Answer: \\frac{1}{2}")), True)
check("exact alias matches", grade.matches(EXACT, grade.extract(EXACT, "Answer: 0.5")), True)

# --- rational / ordered ----------------------------------------------------
check("rational", grade.matches(RAT, grade.extract(RAT, "Answer: 3/4")), True)
check("ordered", grade.matches(SEQ, grade.extract(SEQ, "Answer: a, b, c")), True)

# --- COMPSEC line sets: subset of the audited range, at least one ----------
check("line exact", grade.matches(SEC, grade.extract(SEC, "Answer: 42")), True)
check("line range subset", grade.matches(SEC, grade.extract(SEC, "Answer: 41,42")), True)
check("line outside range", grade.matches(SEC, grade.extract(SEC, "Answer: 40")), False)
check("line partly outside", grade.matches(SEC, grade.extract(SEC, "Answer: 42,50")), False)

# --- a missing answer line is a miss, never a lucky match ------------------
check("no answer line", grade.extract(INT, "the result is 204"), "?")
check("no answer line is wrong", grade.matches(INT, grade.extract(INT, "the result is 204")), False)
check("empty generation", grade.matches(MC4, grade.extract(MC4, "")), False)


def main() -> int:
    failed = 0
    for name, got, want in TESTS:
        if got != want:
            print(f"FAIL {name}: got {got!r}, want {want!r}")
            failed += 1
    print(f"{len(TESTS) - failed}/{len(TESTS)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
