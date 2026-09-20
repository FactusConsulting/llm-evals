# Archived eval runs

Superseded, invalid and unjudged runs, moved out of the live `results/` so
[`../../DASHBOARD.md`](../../DASHBOARD.md) shows one row per model and every live
directory backs a published number. **Nothing here is deleted** — it is moved with
`git mv` and kept for forensic value.

## Run directories

- **Early / abandoned builds:** `gemma4-26b-moe`, `gemma4-31b-nvfp4`, the bare
  `gemma4-4b` / `gemma4-26b` dirs.
- **Negative results:** `gemma4-31b-q8_0-ollama-doa-*` (ollama fabricates tool calls —
  dead on arrival).
- **Single-judge (noisier, ~4-5 pt stricter, not comparable to multi-judge):**
  `gemma4-26b-q6k-turbo-ai-infer1-singlejudge`,
  `12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md`.
- **Partial / invalid runs:** `qwen3-coder-next-80b-*-partial`, loop
  `qwen3.6-35b-a3b-INVALID-4096tok`.
- **Superseded by a newer build of the same model:** older `gemma4-26b-q6k*`
  (→ `-v2-ai-infer2`), `gemma4-12b-bf16-65k*` (→ `-q4-ai-infer3`),
  `gemma4-31b-q4km/q5km*` (→ `-q6k-128k`), the `qwen35-35b-a3b-q5km-*` ctx/KV sweep
  including its `-2x262144-q4kv` representative, `qwen35-9b-vllm` (no knowledge
  ratings).
- **Sampler-tuning experiments:** loop `gemma4-*-dry08/dry15-*`.
- **Responses that were never judged and support no number anywhere:**
  `mistral-small-3.2-24b-vllm-gx10` (unsloth HF repo garbles the tokenizer — the
  responses are the garble), `mistral-small-4-119b-nvfp4-vllm-gx10` (the 66 GB NVFP4
  checkpoint OOMs the 121 GiB box during load, so there are no responses at all),
  `qwen35-35b-a3b-q5km-2x262144-q4kv`.

## Closed cross-model verdicts

Settled comparisons. Their conclusions are summarised in the DASHBOARD; these are
the full arguments and the raw tables.

- `GX10-CAMPAIGN-COMPARISON.md` — the GX10 vLLM campaign, closed 2026-07. Knowledge
  saturated across the four original models; agentic was the differentiator
  (Nemotron 98.78% knowledge / 57.3% agentic is the cleanest proof that one-shot Q&A
  is not autonomous delivery). Records the two caveats the DASHBOARD repeats: AG27
  never ran, and the fleet's 87.0% agentic figure has no artefact in this repo.
- `gemma4-31b-vs-26b-verdict.md` (2026-04-14) — 31B does not beat 26B-A4B; the
  Part B code failures are identical at Q4 and Q5, so they are structural, not
  quantisation. Includes the rejected 3×/4× GPU purchase analysis and the measured
  ~42 bytes/token turbo4 KV figure for 31B dense.
- `gemma4-26b-q5-vs-q6-verdict.md` (2026-04-14) — Q6_K beats Q5_K_L by 15 pp on
  Part B with nothing else moving; the extra context Q5 buys is worthless.

Both 2026-04 verdicts were scored by a single ad-hoc Opus judge on a 385-point
scale, so their absolute numbers are not comparable with the current two-judge
percentages. The direction of their deltas is what survives.

## First-generation scaffolding

`result-schema.json`, `examples/llama-3.1-70b/N3.json` and `evaluator-prompt.md` are
the original one-JSON-file-per-question workflow, replaced by the chunked suite and
the `judge-llm-eval` skill. Kept because they document what the schema used to be.

## Dangling `chunks` symlinks

Several archived dirs point `chunks` at a sibling that has since moved, and four
live dirs point at `gemma4-26b-q6k`, which is here. The questions themselves are
intact in whichever directory holds the real copy; only the pointers are stale. To
re-judge one of those runs, repoint its link first, e.g.

```bash
ln -sfn ../_archive/gemma4-26b-q6k/chunks results/gemma4-26b-q6k-458k-turbo4-v2-ai-infer2/chunks
```
