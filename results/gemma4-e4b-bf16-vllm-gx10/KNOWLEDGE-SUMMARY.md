# Gemma 4 E4B BF16 (GX10, vLLM) — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. Served via vLLM
`v0.23.0-aarch64-cu129` BF16 (`gemma4-e4b`, gemma4 reasoning + tool parsers, ngram).

| Run | Pass A | Mean |
|---|---|---|
| run1 | 95.95% | 95.95% |
| run2 | 95.68% | 95.68% |
| run3 | 96.62% | 96.62% |

**Overall: 96.08%** (2133/2220; spread 95.68–96.62, stdev ~0.40)

Per-chunk (mean): chunks 1–8 = 92–100%; **chunk9 (scenarios) = ~89%** (88.3 / 85.0 / 93.3).
Remarkable for a 4B-class model — knowledge essentially tied with the much larger peers.

## vs BF16 (llama.cpp, same model)
- llama.cpp E4B BF16 = **96.67%** → vLLM BF16 is **−0.59 pt** — a **tie** (judge-method noise;
  vLLM scored Opus-4.8, the llama.cpp baseline older/looser). No knowledge cost on vLLM.

## Verdict (provisional)
E4B holds full knowledge on vLLM BF16 (tie with llama.cpp). But see VERDICT.md — **agentic
drops ~18 pt on vLLM** (67.7 vs 86.0), the one place E4B's elastic/centroid-head arch does
NOT serve cleanly on vLLM's Gemma4 path. Knowledge & loop are unaffected.

Raw per-question ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
