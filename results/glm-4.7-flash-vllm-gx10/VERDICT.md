# GLM-4.7-Flash 30B-A3B (MoE, reasoning) — vLLM **0.24** GX10 — evaluation

The headline result of the vLLM-0.24 re-test: **GLM-4.7-Flash was fully BLOCKED on vLLM
0.23** (`Glm4MoeLiteForCausalLM` → `AssertionError` at engine init) and is a **strong, fast,
usable model on vLLM 0.24**. Served via `vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404`
BF16, 32k ctx. No llama.cpp baseline (not a fleet model) → vLLM-only.

| Dimension | GLM-4.7-Flash (BF16, vLLM 0.24) | Notes |
|---|---|---|
| Knowledge (~370q, 3-judge Opus-4.8) | **96.80%** (spread 1.62pp) | competitive with the Gemma/Qwen band |
| Loop (24 gens) | **2 spirals** ⚠️ | some loop-resistance weakness (like Mistral Medium) |
| Speed | **~20 tok/s** | FAST — MoE 3B-active; unlike the dense ~3 tok/s models |
| Agentic | not yet run | fast enough to run; deferred to keep the 0.24 sweep moving |

## Why it matters
This is the proof that **the 0.23 "only Gemma/Qwen" wall was a vLLM-version limit, not a
model limit**. The same GX10, the same Blackwell/sm_121, the same weights — 0.23 refused to
init the engine; 0.24 runs it at 20 tok/s with 96.8% knowledge. A 30B-A3B MoE reasoning model
at 20 tok/s + ~97% knowledge is a genuinely usable local model (coding/agentic candidate — its
intended niche).

## Verdict
**Adopt-worthy on vLLM 0.24.** Fast, strong knowledge, reasoning-capable. Watch the 2 loop
spirals under open-ended tasks. Run the agentic suite next to confirm the coding/tool-use
profile. And — critically — 0.24 is now the image to re-test every other 0.23-blocked model on.

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Loop: `../../loop-detection/results/glm-4.7-flash/` (24 gens, 2 spirals).
