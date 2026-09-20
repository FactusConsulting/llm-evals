# External benchmarks

Runs of **third-party / standard** LLM benchmarks against our fleet — as opposed
to the **custom** evals at this repo's top level (`agentic/`, `loop-detection/`,
and the `judge-knowledge.py` knowledge eval).

Keep them separate on purpose: our custom evals measure *our* specific
agentic/knowledge priorities; these external ones give standardized,
comparable-to-the-field numbers maintained (and contamination-tracked) by their
upstream authors. Anything under `external/` is NOT our test.

## Layout

```
external/
  <suite>/                  # e.g. lm-eval-harness, livebench, tau-bench, swe-bench
    README.md               # how that suite was run (framework + version + config)
    <model>/                # gemma4-12b-q4-ai-infer3 | gemma4-12b-q8-ai-infer2 | gemma4-26b-ai-infer1
      <benchmark>/          # ifeval, gpqa, ...
        results.json        # raw harness output
        run-config.txt      # exact command + framework version + date
```

## Models (all reached via LiteLLM `https://llm.lwa.dk/v1`)

| Benchmark model name | Host | Serving |
|---|---|---|
| `gemma4-12b-q4` | ai-infer3 | Gemma 4 12B Q4_K, 131k |
| `gemma4-12b`    | ai-infer2 | Gemma 4 12B Q8, 260k |
| `gemma4-26b`    | ai-infer1 | Gemma 4 26B-A4B Q6_K |

## Suites

- **ds4-eval** — 142 deterministically graded cases curated by antirez/ds4:
  GPQA Diamond, SuperGPQA, AIME 2025, defensive code review, MMLU-Pro,
  OlympiadBench, LiveBench, NIST Juliet. No judges. See `ds4-eval/README.md`.
- **lm-eval-harness** (EleutherAI) — IFEval, GPQA, ... via the OpenAI-compatible
  LiteLLM endpoint (`local-chat-completions`).
- **tau2** / **BFCL** — installed on the eval server, not yet wrapped.
- _(planned)_ SWE-bench Verified, Terminal-Bench, Aider polyglot.

## Driving them

`RUNBOOK.md` has the three tiers (`gate` / `rank` / `deep`), what each is for,
the current state of every suite, and the one blocker on the eval server.
`bin/eval-tier` runs a tier. `provision/setup-eval-server.sh` builds the box.

Read `RUNBOOK.md` before trusting a number from here: it says which suites
actually run today and which are scaffolding.

> Tip (from the survey): run each task N times and report consistency (τ-bench's
> `pass^k`), not just the mean — stronger signal than a single pass.
