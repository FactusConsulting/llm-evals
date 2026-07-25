# Gemma 4 31B BF16 (GX10, vLLM) — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. Served via vLLM
`v0.23.0-aarch64-cu129` BF16 (`gemma4-31b`, dense, gemma4 reasoning + tool parsers,
ngram). Dense 31B ~3.9 tok/s on the GX10 (bandwidth-bound).

| Run | Pass A | Mean |
|---|---|---|
| run1 | 98.11% | 98.11% |
| run2 | 98.78% | 98.78% |
| run3 | 98.24% | 98.24% |

**Overall: 98.38%** (2184/2220; spread 98.11–98.78, stdev ~0.28)

Per-chunk (mean): chunks 1–8 = 97.5–100% (chunk6 a clean 100% all runs);
**chunk9 (scenarios) = ~90.6%** — the only soft spot, as for every Gemma size.
The strongest of the Gemma family on knowledge, as expected for the largest dense.

## vs Q6_K (llama.cpp, same model)
- Q6_K llama.cpp = **98.92%** → BF16 vLLM is **−0.54 pt** — a **tie** within judge-method
  noise (vLLM scored Opus-4.8, the Q6_K baseline Opus-4.6). No knowledge cost on vLLM.

## Verdict (provisional)
31B BF16 on vLLM holds full knowledge (tie with Q6_K llama.cpp), the family's highest.
See VERDICT.md — loop 0 spirals, and the **first agentic number for the 31B** (88.0%,
no prior llama.cpp agentic run existed).

Raw per-question ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
