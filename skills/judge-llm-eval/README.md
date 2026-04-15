# judge-llm-eval — stable multi-judge scoring for the LLM eval suite

A Claude Code skill that scores knowledge-eval runs from this repo with low
judge-to-judge variance. Replaces the ad-hoc "spawn one Opus agent per run"
workflow that produced ±1.5pp swings on identical model output.

## Why this exists

The eval suite (chunks 1-9) has ~370 questions per run. Scoring all of them
against a rubric is a judgment call on borderline cases. A single Opus agent
applies the rubric slightly differently each time it's spawned, producing
inter-run variance that masks real model-quality changes.

This skill addresses that with three mechanisms:

1. **Reference answer key** — canonical correct answers for every question,
   written once. Judges compare model output to reference for fact-checking
   instead of evaluating from scratch.
2. **Two parallel independent judges** — both score everything, results are
   diffed.
3. **Super-judge for disagreements** — a third Opus agent ("overdommer") sees
   both judges' ratings + justifications and resolves disagreements with
   final reasoning. Manual review never required.

## Files

```
skills/judge-llm-eval/
├── SKILL.md                          # main skill documentation + workflow
├── README.md                         # this file
├── prompts/
│   ├── rubric.md                     # the scoring rubric
│   ├── judge.md                      # template for judge A/B
│   └── super-judge.md                # template for the overdommer
├── answers/
│   ├── chunk1-networking-linux.md
│   ├── chunk2-k8s-dev.md
│   ├── chunk3-opentofu-ansible.md
│   ├── chunk4-go-rust.md
│   ├── chunk5-dotnet-python.md
│   ├── chunk6-js-bash-powershell.md
│   ├── chunk7-8-architect.md         # imported from results/architect/answers.md
│   └── chunk9-scenarios.md
├── schemas/
│   └── judge-output.json             # JSON schema for judge.json output
└── validators/                       # (optional, future) Part B code validators
    └── ...
```

## Usage

Inside Claude Code:

```
/judge gemma4-26b-q6k-458k-turbo4-v2-ai-infer2/run1
```

The skill instructs Claude (the orchestrator) to:

1. Read all 9 chunk responses + reference answers
2. Spawn 2 parallel Opus judges with the judge prompt
3. Diff their per-question outputs
4. Spawn super-judge for disagreements (if any)
5. Aggregate to `results/<model>/run<N>/judge.json`
6. Write human-readable summary to `judge-summary.md`

Token cost per run: ~85-95k tokens (cheap for the variance reduction).

## Reference answer principle

Reference answers are **gold standard, not contract**. Judges are explicitly
instructed:

> "If a model's answer differs from the reference but is technically correct,
> still rate it pass and set `alternative_acceptable: true`."

Tracking `alternative_acceptable` over time identifies questions where the
reference is too narrow and should be expanded.

## Maintenance

When the eval suite changes (new questions, new chunks), update the answer
files in `answers/`. When a question consistently triggers
`alternative_acceptable`, rewrite that reference entry to accept the
divergent valid forms.

## Adding a new model to compare

Just run `/judge <new-model-dir>/<run>` for each run of the new model. Then
write a verdict markdown comparing the new model's mean against existing
models' means.

## Future — Part B deterministic validators

Chunk 9 Part B is the highest-variance area because it asks for code/IaC.
Eventually `validators/` will run extracted code through:

- `terraform validate` (with stub backend)
- `kubectl apply --dry-run=client -f -`
- `shellcheck`
- `python -m py_compile`
- `jq -n`

Validator results become a hard signal to judges: code that fails syntax
validation cannot rate higher than partial. This eliminates judge variance
on the scariest part of the eval.
