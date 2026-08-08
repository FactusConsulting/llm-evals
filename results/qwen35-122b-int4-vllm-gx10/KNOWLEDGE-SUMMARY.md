# Qwen3.5-122B-A10B GPTQ-Int4 (GX10, vLLM) — Knowledge eval

6-judge (Opus-4.8, 2/run × 3 runs), 370 questions/run. Served via vLLM
`v0.23.0-aarch64-cu129` GPTQ-Int4 on the GX10 (the only ≥-fitting weight on
121 GB UMA; Q5 GGUF is blocked on vLLM for qwen35moe).

| Run | A | B | Mean |
|---|---|---|---|
| run1 | 98.38% | 96.76% | 97.57% |
| run2 | 96.89% | 94.05% | 95.47% |
| run3 | 95.54% | 97.97% | 96.76% |

**Overall: 96.60%** (4289/4440; spread 94.05–98.38, stdev 1.46)

## vs Q5_K_M (llama.cpp, same model)
- Q5_K_M GX10 = **98.92%** → Int4 is **−2.32 pt RAW**.
- **CONFOUND:** the Q5 number was scored by **Opus-4.6** judges (campaign standard); this Int4 run was scored by **Opus-4.8** judges (the 4.6 metered key is dry). Opus-4.8 judges noticeably stricter, so the gap is NOT apples-to-apples. A same-judge re-score of Q5 (or the 35B-A3B BF16 anchor) is needed to attribute how much of the 2.3 pt is quantization vs judge model.
- **Weak spot:** chunk9 (scenarios) consistently lowest — 45–56/60 (~75–93%), vs ~96–99% on the knowledge chunks. Int4 degrades most on multi-step scenario reasoning.

## Verdict (provisional)
Int4 GPTQ is in the **same ballpark** as Q5 on knowledge — not dramatically degraded — but the RAW 2.3 pt drop can't be cleanly separated from judge-model strictness. If the Opus-4.8 judges run ~2 pt strict (plausible vs the 4.6 baseline), Int4 ≈ Q5; if not, Int4 costs ~2 pt of knowledge for fitting on vLLM. Scenario reasoning is the consistent weak point regardless.

Raw per-question ratings: `run{1,2,3}/chunk{1-9}-ratings-pass{A,B}.json`.
