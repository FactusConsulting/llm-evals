# Archived eval runs

Superseded / not-current eval runs, moved out of the live `results/` so [`../../DASHBOARD.md`](../../DASHBOARD.md) only shows the latest generation per model. Nothing here is deleted — kept for forensic value.

Why each was archived:
- **Early / abandoned builds:** `gemma4-26b-moe`, `gemma4-31b-nvfp4`, the bare `gemma4-4b` / `gemma4-26b` dirs.
- **Negative results:** `gemma4-31b-q8_0-ollama-doa-*` (ollama fabricates tool calls — dead-on-arrival).
- **Single-judge (noisier, ~4–5pt stricter, not comparable to multi-judge):** `gemma4-26b-q6k-turbo-ai-infer1-singlejudge`, `12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md`.
- **Partial / invalid runs:** `qwen3-coder-next-80b-*-partial`, loop `qwen3.6-35b-a3b-INVALID-4096tok`.
- **Superseded by a newer build of the same model:** older `gemma4-26b-q6k*` (→ `-v2-ai-infer2`), `gemma4-12b-bf16-65k*` (→ `-q4-ai-infer3`), `gemma4-31b-q4km/q5km*` (→ `-q6k-128k`), the `qwen35-35b-a3b-q5km-*` ctx/KV sweep (kept `-2x262144-q4kv`), `qwen35-9b-vllm` (no knowledge ratings).
- **Sampler-tuning experiments:** loop `gemma4-*-dry08/dry15-*`.
