# Gemma 4 31B BF16 (vLLM, GX10) — full evaluation

Served via vLLM `v0.23.0-aarch64-cu129`, BF16 (~62 GB), gemma4 reasoning + tool-call
parsers, gpu-mem-util 0.85, ngram spec-decode. Dense 31B → ~3.9 tok/s (bandwidth-bound)
on the GX10. The full-precision 31B only fits the 121 GB GX10.

| Dimension | BF16 (vLLM, GX10) | Q6_K (llama.cpp) | Δ |
|---|---|---|---|
| Knowledge (~370q) | **98.38%** (3-judge Opus-4.8) | 98.92% | tie* |
| Agentic (30-task) | **88.0%** (264/300, 27/30 verified) | — (no prior run) | NEW |
| Loop (24 gens) | **0 spirals** ✅ | 0/9 (partial, q4km build) | tie |

\* Knowledge: tie within judge-method noise. The 31B is the Gemma family's knowledge
ceiling (98.38%), edging the 26B (98.24) and 12B (97.07) — but only by noise-level margins.

## Verdict
31B BF16 on vLLM is a fully-viable, strong serving: family-highest knowledge (tie with
Q6_K llama.cpp), 0 loop spirals, and **88.0% agentic** — the first agentic measurement for
the 31B (the llama.cpp side never had an agentic run). No engine penalty. Caveat: dense
31B is **slow** (~3.9 tok/s) — the knowledge edge over the 26B-A4B MoE (98.38 vs 98.24, a
tie) does NOT justify the ~3-4× throughput cost vs the MoE for production. As a capability
data point: vLLM serves the 31B at full quality; as a serving choice, the MoE 26B/35B win
on speed for no real quality loss.

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Agentic: `../../agentic/results/gemma4-31b/`.
Loop: `../../loop-detection/results/gemma4-31b/*-score.json` (24 gens, 0 spirals).
