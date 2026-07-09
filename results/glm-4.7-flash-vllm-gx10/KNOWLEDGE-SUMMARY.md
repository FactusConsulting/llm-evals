# GLM-4.7-Flash 30B-A3B (MoE, reasoning) — vLLM 0.24 — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. Served via
`vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404` BF16, 32k ctx. **Blocked on 0.23**
(`Glm4MoeLite` AssertionError); works on 0.24.

| Run | Pass A | Mean |
|---|---|---|
| run1 | 96.22% | 96.22% |
| run2 | 96.35% | 96.35% |
| run3 | 97.84% | 97.84% |

**Overall: 96.80%** (2149/2220; spread 96.22–97.84, stdev ~0.74)

Per-chunk (mean): chunks 4/5/7/8 = 98–100%, chunk6 ~98%, chunks 2/3 ~93–100%,
chunk1 ~93%; chunk9 (scenarios) ~89%. Reasoning model — verbose (thinking + answer);
the judges scored the final answers. Competitive with the Gemma/Qwen band.

## Notes
- **~20 tok/s** (MoE 3B-active) — fast; a usable interactive/agentic model, unlike the
  dense ~3 tok/s models (Mistral Medium, Granite).
- No llama.cpp baseline → vLLM-only. The story is the **0.23→0.24 unblock**, not an engine delta.

Raw ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
