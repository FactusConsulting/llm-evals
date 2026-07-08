# IBM Granite 4.1 30B (hybrid Mamba/Transformer, vLLM GX10) — evaluation

Owner's test-order #4: wanted tested for **stability** (tool-calling, JSON, RAG,
policy-following, enterprise-assistant behaviour), not raw intelligence. Dense-ish 30B
but a **hybrid Mamba-2/Transformer** arch. Served via vLLM `v0.23.0-aarch64-cu129` BF16,
131k ctx, ngram spec-decode. No llama.cpp baseline (not a fleet model) → vLLM-only.

| Dimension | Granite 4.1 30B (BF16) | Notes |
|---|---|---|
| Knowledge (~370q, 3-judge Opus-4.8) | **96.40%** (spread 0.95pp) | solid — around the Gemma E4B/12B band |
| Loop (24 gens) | **0 spirals** ✅ | (finalizing; 0 through the first pass) |
| Agentic | **not run** | ~3 tok/s → the 30-task harness is impractical; the speed itself is the finding |

## The problem: ~3 tok/s (Mamba layers unoptimized on vLLM 0.23 / Blackwell)
A "30B" ran at **~3 tok/s** here — 17–30 min per eval chunk, several chunks blew a
30-min per-request timeout. That is dense-128B-slow, NOT what a 30B should do. Cause:
Granite 4.1's **hybrid Mamba-2/Transformer** layers are not efficiently supported on
vLLM 0.23's sm_121 (Blackwell) path — the Mamba mixer runs unoptimized. Same ~3 tok/s
wall as the dense Mistral Medium 128B.

## Verdict
Knowledge is solid (96.4%) and the model is built for exactly the **stability / enterprise-
assistant** profile the owner wanted — BUT at **~3 tok/s it is not usable as a responsive
local assistant** on this box, and the agentic/tool-calling behaviour the owner actually
cared about couldn't be measured because of it. The blocker is serving efficiency (Mamba
on vLLM 0.23/Blackwell), not the model. Re-evaluate if a newer vLLM (or a llama.cpp build
with proper Mamba-2 kernels) speeds it up; until then, not a practical pick here.

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Loop: `../../loop-detection/results/granite-4.1-30b/`.
