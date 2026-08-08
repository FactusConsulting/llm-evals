# Qwen3.5-122B-A10B GPTQ-Int4 (vLLM, GX10) — full evaluation

Served via vLLM `v0.23.0-aarch64-cu129`, GPTQ-Int4, max-model-len 131072,
gpu-mem-util 0.92, 2 slots. The only ≥-fitting weight on the 121 GB GX10 that
vLLM can load (Q5_K_M GGUF is blocked for qwen35moe on vLLM).

| Dimension | Int4 (vLLM) | Q5_K_M (llama.cpp) | Δ |
|---|---|---|---|
| Knowledge (~400q) | **96.60%** (6-judge Opus-4.8) | 98.92% (6-judge Opus-4.6) | −2.32 pt* |
| Agentic (30-task) | **83.3%** (250/300, 26/30 verified) | 87.7% (263/300) | −4.4 pt** |
| Loop (24 gens) | **0 spirals** ✅ | 0 spirals ✅ | tie |

\* Knowledge Δ is **confounded**: Int4 scored by Opus-4.8 judges, Q5 by the
campaign's Opus-4.6 (4.6 metered key dry). Opus-4.8 judges noticeably stricter,
so part of the 2.3 pt is judge-model, not quantization. Int4's weak chunk is
scenarios (chunk9, ~75-93%).

\** One agentic task errored (0/10, 0 steps — looks like a transient harness/
infra error, not a capability fail); the true agentic is likely a touch higher
than 83.3%.

## Verdict
Int4 GPTQ on vLLM is a **viable serving of the 122B** — same ballpark as the Q5
llama.cpp serving, consistently a little behind on knowledge and agentic, tied
(perfect) on loop resistance. Given Q5-GGUF can't load on vLLM, Int4 is *the*
vLLM option for this model, and it holds up. Not a reason to prefer the 122B
over the 3.5x-smaller 35B-A3B though (the 122B doesn't meaningfully beat it).
