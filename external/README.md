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

- **lm-eval-harness** (EleutherAI) — IFEval, GPQA, ... via the OpenAI-compatible
  LiteLLM endpoint (`local-chat-completions`).
- _(planned)_ LiveBench (contamination-free, monthly), τ-bench (`pass^k`
  consistency), SWE-bench Verified, Terminal-Bench.

> Tip (from the survey): run each task N times and report consistency (τ-bench's
> `pass^k`), not just the mean — stronger signal than a single pass.
