# Loop Detection Eval Suite

Tests a model's tendency to "spin out" — enter a reasoning loop, repeat conclusions, or fail to stop cleanly on open-ended agentic tasks.

Designed for: Qwen3.5-9B, Qwen3.5-27B, Gemma 4 E4B, Gemma 4 26B running under OpenClaw.

## Why this exists

The existing agentic eval (`agentic/`) measures whether a model can complete a task at all. This suite measures something orthogonal: whether the model knows when to stop. Production failures have been observed in three modes:

1. **n-gram repetition** — model emits the same phrase/sentence in a loop (caught well by DRY sampler)
2. **reasoning spiral** — model re-states its analysis in different words across many paragraphs without advancing
3. **task-expansion creep** — model keeps adding sub-tasks and "we should also check..." clauses after a clear stopping point

These three failure modes are distinct and require different mitigations. This suite distinguishes between them.

## Scenarios

| ID | Category | What it probes |
|----|----------|---------------|
| LD1 | multi-step-research | Branch audit across many repos — enumeration + tracking, no clean stop |
| LD2 | iterative-fix | CI fix where the previous two attempts were identical — should not try same thing again |
| LD3 | open-ended-code-review | Large code review — model must not recap the code, must stop after review |
| LD4 | ambiguous-stopping | Release prep with no explicit scope — model must self-impose a stopping point |
| LD5 | state-tracking | K8s resource audit across 3 batches — must maintain state without duplicating or losing rows |
| LD6 | iterative-fix | Systemd restart loop — root cause visible in provided data, model must converge and stop |
| LD7 | open-ended-code-review | JWT PR review with a recap trap — must not summarize the PR before or after reviewing |
| LD8 | multi-step-research | Ansible role usage audit — enumerate 12 roles against 5 playbooks, stop after answer |
| LD9 | ambiguous-stopping | "Plan the Postgres upgrade" — must self-limit to ~400-600 words, no appendices |
| LD10 | iterative-fix | Fix a script without pandas (stdlib only) — must stop after 3 attempts max |
| LD11 | state-tracking | Cross-repo SDK version tracking — 5 services, must correctly identify latest version |
| LD12 | ambiguous-stopping | Message queue recommendation — must compare exactly 3 options, end with terminal phrase |

## Scoring

Max: **10 points per scenario, 120 total.**

| Dimension | Max | Measured by |
|-----------|-----|-------------|
| Completion | 4 | Judge model |
| Termination | 3 | Automated (word count, terminal phrase, bigram overlap) |
| Accuracy | 2 | Judge model |
| Economy | 1 | Judge model |

See `rubric.md` for per-scenario pass/partial/spiral criteria and correct answers.

## Running

### Single scenario (no judge, automated checks only)
```bash
./run-eval.sh \
  --model-url http://192.168.2.170:8001 \
  --model-name qwen35-27b \
  --scenario LD3
```

### Full suite
```bash
./run-eval.sh \
  --model-url http://192.168.2.170:8001 \
  --model-name qwen35-27b
```

### Full suite with judge scoring
```bash
./run-eval.sh \
  --model-url http://192.168.2.170:8001 \
  --model-name qwen35-27b \
  --judge-url http://192.168.2.170:8000
```

The `--judge-url` endpoint is called after each response to score Completion, Accuracy, and Economy using the rubric. Use a strong judge (Claude Opus or similar) for reliable results. The 27B model can self-judge in a pinch but will be lenient on its own outputs.

### Both models
```bash
# 9B
./run-eval.sh --model-url http://192.168.2.171:8001 --model-name qwen35-9b --judge-url http://192.168.2.170:8000

# 27B
./run-eval.sh --model-url http://192.168.2.170:8001 --model-name qwen35-27b --judge-url http://192.168.2.170:8000
```

### Flags
| Flag | Default | Description |
|------|---------|-------------|
| `--model-url` | http://192.168.2.170:8001 | Inference API endpoint |
| `--model-name` | (required) | Model name for API and result directory |
| `--api-key` | $LLAMA_API_KEY | Bearer token (reads env if not set) |
| `--scenario` | all | Run only one scenario (e.g., LD3) |
| `--judge-url` | (none) | If set, run judge scoring after each response |
| `--max-tokens` | 4096 | Max tokens for model response |
| `--temperature` | 0.1 | Sampling temperature |
| `--parallel` | off | Run all scenarios concurrently |
| `--verbose` | off | Show word count and prompt size |

## Output

```
results/<model-name>/
  LD1-branch-audit-<timestamp>-response.txt
  LD1-branch-audit-<timestamp>-score.json
  LD2-ci-fix-loop-<timestamp>-response.txt
  LD2-ci-fix-loop-<timestamp>-score.json
  ...
```

Each score JSON:
```json
{
  "scenario": "LD3",
  "word_count": 412,
  "spiral_flags": [],
  "is_spiral": false,
  "auto_termination_score": 3,
  "judge": {
    "completion": 4,
    "accuracy": 2,
    "economy": 1,
    "verdict": "pass",
    "brief_justification": "..."
  },
  "total_score": 10
}
```

## Verdict Thresholds

| Score | Interpretation |
|-------|---------------|
| 108-120 (90%+) | Stable — suitable for production agentic tasks |
| 84-107 (70-89%) | Minor looping — monitor, consider tuning DRY sampler |
| 60-83 (50-69%) | Significant looping risk — requires DRY sampler or strict n_predict cap |
| <60 (<50%) | High looping risk — not suitable for open-ended agentic tasks without heavy mitigation |

## Automated Spiral Signals

The grader checks these before the judge sees a response:

| Signal | What it catches |
|--------|----------------|
| Paragraph bigram overlap >85% | n-gram style repetition spiral |
| First/last 200-word bigram overlap >60% | Task recap at end of response |
| Missing required terminal phrase | LD12 only — "RECOMMENDATION COMPLETE." |
| Word count exceeded | LD9 (>800), LD12 (>300) |
| Repeated action line in fix scenarios | LD2, LD6, LD10 — same diagnostic step twice |

## Interpreting Results

**DRY sampler effectiveness**: Compare LD2/LD6/LD10 (iterative-fix) scores with and without DRY sampler (`--dry-multiplier 0.8` in llama.cpp). These scenarios are most sensitive to n-gram suppression.

**Thinking mode regression**: Qwen3 models with thinking enabled tend to spiral in LD4, LD9, LD12 (open-ended, no external tool calls). Compare `enable_thinking=false` vs default.

**9B vs 27B comparison**: The 9B model tends to loop on LD1 and LD11 (multi-step state tracking with many items) because it loses early-batch state. The 27B model tends to loop on LD9 and LD12 (overproduction on open-ended tasks) due to higher verbosity.

## Connection to Production Failure Modes

| Known production trigger | Most relevant scenarios |
|--------------------------|------------------------|
| Branch audit across all FactusConsulting repos | LD1, LD8, LD11 |
| Long CI fix loops (same fix retried) | LD2, LD6, LD10 |
| Large multi-file code review (recaps) | LD3, LD7 |
| Open-ended task with no stopping condition | LD4, LD9, LD12 |
| State tracking across many sequential steps | LD5, LD11 |
