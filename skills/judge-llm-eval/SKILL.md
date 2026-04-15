---
name: judge-llm-eval
description: Score a model's eval responses using a stable two-judge + super-judge workflow with reference answers. Use when the user runs `/judge <model-dir>/<run-num>` or asks to score an eval run. Eliminates judge variance via reference answer key, parallel independent judges, and automatic disagreement resolution.
---

# Judge LLM Eval — Stable Multi-Judge Scoring

This skill scores a single eval run from `llm-evals/results/<model>/<run-num>/`
using a layered judging architecture designed to eliminate the ~1.5pp judge
variance we observed with single-judge ad-hoc scoring.

## Architecture

```
1. PARALLEL — Two independent Opus judges (A + B)
   Each sees: rubric + answer key + model response
   Each emits: per-question JSON (rating, points, justification, alt_acceptable)

2. AUTOMATED — Compare A vs B per question
   Agree    → final rating accepted
   Disagree → flagged for super-judge

3. SUPER-JUDGE (overdommer) — Resolves disagreements
   Sees: question, answer key, model response,
         A's rating + justification, B's rating + justification
   Returns: final rating with reasoning

4. AGGREGATE — JSON output with full audit trail:
   - per-question results
   - inter-rater agreement %
   - super-judge override count
   - alternative_acceptable count (reference too narrow)
```

## Key principle — reference answers are gold standard, NOT contract

The reference answer key is one canonical valid solution. Models often produce
correct answers that differ in wording, structure, or approach. Judges are told:

> "The reference is ONE valid solution. If the model's answer differs but is
> technically correct, more elegant, or uses a smarter pattern, still rate it
> pass. Use the reference to verify factual accuracy of specific claims
> (numbers, syntax, command flags) — not to demand identical wording."

When a judge accepts a model's deviation as still-correct, they set
`alternative_acceptable: true`. Tracking this stat over runs reveals
questions where the reference is too narrow and should be widened.

## Inputs

| Argument | Meaning |
|---|---|
| `<model-dir>` | Path under `results/`, e.g. `gemma4-26b-q6k-458k-turbo4-v2-ai-infer2` |
| `<run-num>` | Run number (1, 2, 3, …) |

## Files used

- **Question chunks**: `results/gemma4-26b-q6k/chunks/chunk{1..9}-*.txt` (any `chunks/` dir works — they're identical across models)
- **Reference answers**: `skills/judge-llm-eval/answers/chunk{1..9}-*.md`
- **Judge rubric**: `skills/judge-llm-eval/prompts/rubric.md`
- **Judge prompt template**: `skills/judge-llm-eval/prompts/judge.md`
- **Super-judge prompt template**: `skills/judge-llm-eval/prompts/super-judge.md`
- **Output schema**: `skills/judge-llm-eval/schemas/judge-output.json`

## Outputs

- `results/<model-dir>/run<N>/judge.json` — full audit trail with per-question results
- `results/<model-dir>/run<N>/judge-summary.md` — human-readable summary

## Workflow (executed by you — the orchestrator agent)

### Step 1 — Spawn Judge A and Judge B in parallel

For each of the 9 chunks, spawn TWO Opus agents simultaneously (so 18 agents
in parallel for a single run, OR 9 agent calls each scoring all chunks for
both judges — depends on context budget).

**Recommended**: 2 agents total per run, each scores all 9 chunks. Cheaper
than 18 agents and gives consistent rubric application within each judge.

Each judge gets the prompt from `prompts/judge.md` filled in with:
- The full rubric
- The chunk question file content
- The model response file content
- The reference answer file content (or note "no reference available" for
  any chunk that's not yet built)

Each judge returns JSON matching the schema in `schemas/judge-output.json`.

### Step 2 — Diff judge outputs

For each question in each chunk:
- If `judge_a.rating == judge_b.rating` → accepted, both points equal
- If they disagree → add to `disagreements[]` list

Track aggregate stats:
- `total_questions`
- `agreement_count`
- `disagreement_count`
- `agreement_pct`

### Step 3 — Super-judge for disagreements

If `disagreement_count > 0`, spawn ONE super-judge agent with the prompt
from `prompts/super-judge.md`. It sees ALL disagreements at once (batched)
and returns a final rating per disagreement with reasoning.

If there are 0 disagreements, skip step 3 entirely.

### Step 4 — Aggregate

Compute final scores:
- Per-chunk: passed/partial/failed counts, points, max, percentage
- Overall: total points, total max, percentage
- Chunk 9: separate Part A / Part B / Part C breakdown
- Inter-rater agreement %
- Super-judge override count
- Notable factual errors (extracted from judge justifications where rating=fail)

Write outputs:
1. `judge.json` with full per-question audit trail
2. `judge-summary.md` with the human-readable report

## Comparing across runs

After judging multiple runs of the same model, write a comparison report:
- Mean/median across runs
- Variance (max-min)
- Inter-rater agreement trend
- Reference-too-narrow questions (high `alternative_acceptable` rate)

This lives at `results/<model-dir>/judge-mean.md`.

## Token budget per /judge invocation

- 2 judges × ~30k tokens input + ~10k output = ~80k tokens
- Super-judge (only if disagreements): ~5-15k tokens
- Total per run: ~85-95k tokens

Re-judging 3 runs costs ~280k tokens. Cheap for the variance reduction.

## When things go wrong

- **No reference for a chunk**: Judge falls back to "score from your own knowledge", note in output JSON `reference_unavailable: true`
- **Both judges return malformed JSON**: Re-spawn the offending judge once. If it fails again, log error and use whichever response parses.
- **Super-judge returns malformed JSON**: Take the average of A and B (passable=2, partial=1, fail=0) and round.

## Updating the reference answer key

If a question consistently gets `alternative_acceptable: true` across many runs,
the reference is too narrow. To update:

1. Read the question and the divergent-but-correct answers
2. Spawn an Opus agent: "rewrite this reference answer to accept any of these
   correct variants"
3. Replace the entry in `answers/chunkN-*.md`
4. Note the change in a CHANGELOG (eventually) so historical scores stay
   reproducible against their reference version

## Future extension — Part B deterministic validators

Chunk 9 Part B answers contain code (HCL, YAML, bash, Python, jq). A
companion validator script runs them through real tools:

- `terraform validate` (with stub backend)
- `kubectl apply --dry-run=client -f -`
- `shellcheck`
- `python -m py_compile`
- `jq -n`

Validator results are passed to judges as a **hard signal**. Code that fails
syntax validation cannot be rated higher than partial. This is implemented
separately at `skills/judge-llm-eval/validators/` (see VALIDATORS.md).
