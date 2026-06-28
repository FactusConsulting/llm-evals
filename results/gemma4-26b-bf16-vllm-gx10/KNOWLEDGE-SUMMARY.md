# Gemma 4 26B-A4B BF16 (GX10, vLLM) — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. Served via vLLM
`v0.23.0-aarch64-cu129` BF16 on the GX10 (`gemma4-26b`, `--reasoning-parser gemma4
--tool-call-parser gemma4`). Lighter protocol than the 122B's 6-judge (1 pass/run
vs 2) — justified by the tight cross-run spread.

| Run | Pass A | Mean |
|---|---|---|
| run1 | 98.51% | 98.51% |
| run2 | 97.84% | 97.84% |
| run3 | 98.38% | 98.38% |

**Overall: 98.24%** (2181/2220; spread 97.84–98.51, stdev ~0.29)

Per-chunk (mean across runs): chunks 1–8 = 95–100%; **chunk9 (scenarios) = ~91.6%**
(93.3 / 88.3 / 93.3) — the consistent weak spot, multi-step scenario reasoning.

## vs Q6_K (llama.cpp, same model)
- Q6_K turbo4 (ai-infer2) = **98.56%** → BF16 vLLM is **−0.32 pt RAW** — a **tie within noise**.
- **CONFOUND (same as the 122B):** this BF16 vLLM run was scored by **Opus-4.8** judges
  (the metered 4.6 key is dry); the Q6_K 98.56% baseline was scored by the campaign's
  **Opus-4.6** multi-judge. Opus-4.8 judges noticeably stricter — so on a same-judge basis
  BF16 vLLM is **≈ or marginally ≥** Q6_K llama.cpp. No knowledge cost to serving the 26B
  on vLLM at BF16.

## Verdict (provisional)
BF16 on vLLM holds the 26B's knowledge **fully** — statistically tied with the Q6_K
llama.cpp serving (98.24 vs 98.56, inside both run-spread and judge-model strictness).
Scenario reasoning (chunk9) is the only soft spot, identical to every other 26B serving.

Raw per-question ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
