#!/usr/bin/env python3
"""Per-category summary of one bfcl run directory. Runs on the eval server.

    summarize.py <run-dir> [max-tokens]

bfcl records a failed request as the model's answer ("Error during inference:
...") and the checker then scores it as wrong, so an unreachable endpoint or a
rejected key produces 0% that reads exactly like a weak model. This counts those
cases, and exits 3 when every case was one.

It also counts the cases where a request spent the whole max_tokens budget: the
answer was cut off, usually inside the reasoning, and bfcl scored what was left.

The composite columns in bfcl's own score/*.csv average over every category of
the full benchmark, so for a subset of categories they are not a score. The
per-category accuracies are.
"""
import json
import sys
from pathlib import Path

ERROR_PREFIX = "Error during inference"


def category_of(path: Path, suffix: str) -> str:
    return path.name.removeprefix("BFCL_v4_").removesuffix(suffix)


def flat(tokens) -> list[float]:
    """output_token_count is a number for one request, nested lists for multi-turn."""
    if isinstance(tokens, list):
        return [t for item in tokens for t in flat(item)]
    return [tokens] if isinstance(tokens, (int, float)) else []


def main(run: Path, max_tokens: int) -> int:
    categories: dict[str, dict] = {}
    first_error = None

    for path in sorted(run.glob("result/**/*_result.json")):
        entry = categories.setdefault(category_of(path, "_result.json"), {})
        cases = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
        errors = [c for c in cases
                  if isinstance(c["result"], str) and c["result"].startswith(ERROR_PREFIX)]
        if errors and first_error is None:
            first_error = errors[0]["result"][:300]
        entry["generated"] = len(cases)
        entry["inference_errors"] = len(errors)
        entry["truncated"] = sum(
            1 for c in cases
            if max_tokens and any(t >= max_tokens for t in flat(c.get("output_token_count")))
        )
        entry["max_output_tokens"] = max(
            (t for c in cases for t in flat(c.get("output_token_count"))), default=0
        )

    for path in sorted(run.glob("score/**/*_score.json")):
        entry = categories.setdefault(category_of(path, "_score.json"), {})
        header = json.loads(path.read_text().splitlines()[0])
        entry["correct"] = header["correct_count"]
        entry["scored"] = header["total_count"]
        entry["accuracy"] = header["accuracy"]

    generated = sum(c.get("generated", 0) for c in categories.values())
    errors = sum(c.get("inference_errors", 0) for c in categories.values())
    truncated = sum(c.get("truncated", 0) for c in categories.values())
    summary = {"categories": categories, "generated": generated,
               "inference_errors": errors, "first_inference_error": first_error,
               "truncated": truncated, "max_tokens": max_tokens or None}
    (run / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    print(f"\n{'category':<28}{'correct':>9}{'scored':>8}{'accuracy':>10}"
          f"{'errors':>8}{'truncated':>11}{'max out tok':>13}")
    for name, c in categories.items():
        accuracy = f"{c['accuracy']:.1%}" if "accuracy" in c else "unscored"
        print(f"{name:<28}{c.get('correct', '-'):>9}{c.get('scored', '-'):>8}"
              f"{accuracy:>10}{c.get('inference_errors', 0):>8}"
              f"{c.get('truncated', 0):>11}{c.get('max_output_tokens', 0):>13.0f}")

    if generated == 0:
        print("\nno cases were generated", file=sys.stderr)
        return 3
    if errors == generated:
        print(f"\nevery request failed: {first_error}", file=sys.stderr)
        return 3
    if errors:
        print(f"\n{errors} of {generated} cases are request failures scored as wrong — "
              f"the accuracies above are not the model's. First: {first_error}", file=sys.stderr)
    if truncated:
        print(f"\n{truncated} of {generated} cases spent all {max_tokens} tokens and were "
              f"scored on a cut-off answer.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]), int(sys.argv[2] or 0) if len(sys.argv) > 2 else 0))
