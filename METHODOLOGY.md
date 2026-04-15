# Methodology — why we do it this way

This document explains the design decisions behind the multi-judge evaluation
methodology and the lessons learned that shaped it. If you just want to run an
eval, see `TESTING.md` (short) or `HOW-TO-DRIVE-EVAL.md` (detailed runbook).

## The original problem

We were running model evaluations with a single Claude Opus 4.6 agent as the
judge, scoring one run at a time from scratch. This produced wide variance:

```
Old single-judge methodology (3 runs of same model):
  Run 1: 97.30%
  Run 2: 98.65%
  Run 3: 96.22%
  Range: 2.43 pp
```

A 2.4pp swing on the same model output meant we couldn't tell whether a
1-2pp difference between two models was a real quality difference or noise.

## What's actually varying

Three independent sources of variance:

1. **Model stochasticity** — temperature 0.1 + unique nonces gives ~0.5pp
   stochastic variance per run from the model itself
2. **Concurrent server load** — slot contention from openclaw/opencode adds
   ~0.5pp by injecting timing variance and rare partial responses
3. **Judge interpretation drift** — the biggest contributor, ~1.5-2pp. Each
   ad-hoc Opus agent applies the rubric slightly differently on borderline
   cases. Three agents = three different rubric interpretations.

The fix has to address #3 (the dominant noise source) without making #1 and #2
worse.

## Mechanisms that work

### Mechanism 1 — Reference answer key

For every question in the eval suite, write a canonical correct answer once.
Store under `skills/judge-llm-eval/answers/`. Judges read the reference for
fact-checking specific claims (numbers, syntax, command flags) instead of
evaluating from cold start each time.

**Caveat (this almost killed us)**: when judges have a reference, they fall
into a trap of treating it as a checklist. They mark answers "weaker than
reference" when the model gave a different but equally valid solution. Our
first attempt with reference + strict rubric gave 90.99% mean (vs 97.39%
ad-hoc) — the absolute number dropped 6pp because judges started downgrading
valid alternatives.

**The fix**: rewrite the judge prompt to explicitly say "the reference is
ONE valid solution, NOT a contract" and use a `alternative_acceptable: true`
flag for any answer that differs but is correct. Set a target rate of
10-30% `alternative_acceptable` — if the rate drops below 5%, the judges are
ignoring the principle.

After this fix, mean climbed to 98.56% (matches the ad-hoc 97.39% baseline
within 1pp) AND variance dropped to 0.67pp.

### Mechanism 2 — Two parallel independent judges

Spawn two Opus agents simultaneously, each scoring the same run. Take
`mean(A.points, B.points)` per question. Where they agree, use that rating.
Where they disagree, use the rounded mean.

**Why this works**: Judge A's strict-on-this-question bias and Judge B's
strict-on-that-question bias are uncorrelated. Averaging two independent
judges roughly halves the variance contribution from rubric drift.

**Why it works better than one judge with longer rubric**: making the rubric
more explicit is helpful, but doesn't eliminate per-question variance.
Independent judges actually score the same answer differently and the average
is more accurate than either alone.

### Mechanism 3 — Two-phase evaluation in the judge prompt

The judge prompt has explicit phase 1 / phase 2 structure:

```
Phase 1 — Functional correctness (PRIMARY):
  Ask: "Does the model's answer correctly solve the problem?"
  YES → pass
  PARTIAL → partial
  NO → fail

Phase 2 — Reference fact-check (SECONDARY):
  Use reference ONLY to verify specific claims.
  Don't compare wording, item sets, approach choice, length.
  If Phase 2 catches a real factual error → downgrade by one notch.
  If Phase 2 finds nothing wrong → keep Phase 1 rating.
```

This forces the judge to evaluate the answer's correctness BEFORE looking at
the reference, then use the reference only for narrow fact-checking. It
prevents the "checklist comparison" failure mode.

### Mechanism 4 — Deterministic validators for code (chunk 9 Part B)

Chunk 9 Part B asks for code/IaC. Judges have the highest variance here
because "does this Terraform look right?" is genuinely subjective when
provider semantics aren't part of HCL grammar.

Solution: extract code blocks programmatically and run real validators:

- Bash → `shellcheck -S error`
- Python → `python -m py_compile`
- jq → `jq -n`
- YAML → `python yaml.safe_load_all` + `kubectl apply --dry-run=client`
- HCL → `terraform fmt -check` (looks for `Error:` in stderr)
- JSON → `json.loads`

Validator output is a hard signal: if `shellcheck` says invalid, the code is
invalid. Judges still rate the answer (because validity is necessary but not
sufficient — code can be valid but wrong) but cannot rate above partial when
the validator says ✗.

Extension we haven't built yet: SQL/Go/Rust validators.

## Mechanisms we tried that did NOT work

### Super-judge that re-scores disagreements

We tried having a third "super-judge" agent see disagreements between A and B
and resolve them with its own ruling. The intuition was that a tiebreaker
would smooth over inconsistency.

In practice, the super-judge introduced new variance: each super-judge agent
is an independent Opus call with its own rubric drift. Across 3 runs, three
super-judge agents made different calls on similar disagreements. Final
post-super-judge variance was 3.24pp — *worse* than just taking mean(A,B)
(0.67pp).

**Lesson**: adding more agents adds more variance unless you're careful about
when each one runs. mean(A,B) cancels out drift because A and B see the
SAME questions. A super-judge sees a DIFFERENT subset (only disagreements)
per run, so its drift can't cancel.

**Current architecture**: super-judge is now used for **audit only** (looking
at specific high-stakes disagreements after the fact for the verdict
markdown), not for changing the score.

### Strict reference matching

Our first attempt told judges to compare model output against reference and
score on closeness. This produced too-low absolute scores (90.99% on a 97%
model) because real differences in approach were marked partial.

**Lesson**: the reference is a hint to the judge, not a contract for the
model. The principle is "did the model solve the problem?", not "did the
model match the reference?".

## What we measure to know it's working

Per run:
- **Inter-judge agreement %** — should be 95-98%. Below 90% means the rubric
  is unclear or one judge is misbehaving.
- **`alternative_acceptable` rate** — should be 10-30%. Below 5% means
  judges are too strict (treating reference as contract).
- **Per-judge delta from mean** — should be <0.5pp. Larger means one judge
  has a systematic bias for that run.

Across runs:
- **Mean score range** — should be 0.4-0.9pp for a stable model. Larger
  means slot contention or judge variance.
- **Persistent failure modes** — questions that fail in all 3 runs are real
  model limits. Questions that fail in 1/3 runs are stochastic noise.

## Where this fails (known limitations)

1. **Reference answers can drift out of sync with the eval suite.** If the
   eval suite changes a question, the reference answer must be updated. We
   don't have automated detection of this.

2. **Judges can collude on a wrong rubric interpretation.** If both Opus
   agents share the same blind spot (e.g. both think `kubernetes_csi_volume`
   is a real resource), they'll both pass invalid answers. This is mitigated
   by the deterministic validator for code, but not for prose.

3. **Super-judge audit isn't automated.** When a question has high disagreement
   over multiple runs, a human (or future automated check) should review and
   either fix the reference or fix the rubric. Currently this is manual.

4. **Cost scales with number of judges.** For 3 runs with 2 judges each,
   we spend ~1M tokens of Opus per evaluation. Affordable but not free.

5. **No cross-judge style measurement.** We assume Opus A and Opus B are
   roughly equivalent independent samples, but they're the same underlying
   model. A truly independent second judge (e.g. GPT-5) would catch things
   Opus consistently misses.

## Future improvements

1. **Add SQL/Go/Rust validators** for chunk 9 Part B (currently ~unvalidated)
2. **Auto-update reference answers** when `alternative_acceptable` rate is
   high for a specific question across many runs
3. **Cross-vendor judges** — use Opus + GPT-5 + Gemini 3 as the three
   judges instead of three Opus instances
4. **Hard-fail on validator disagreement** — if validator says ✗ but both
   judges say pass, auto-flag for review
5. **Track judge stability over time** — log which questions cause repeated
   judge disagreement and use that as a signal that the rubric/reference
   needs work
