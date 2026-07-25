# Gemma 4 26B-A4B BF16 (vLLM, GX10) — full evaluation

Served via vLLM `v0.23.0-aarch64-cu129`, BF16, `--reasoning-parser gemma4
--enable-auto-tool-choice --tool-call-parser gemma4`, gpu-mem-util 0.85, ngram
spec-decode. 121 GB UMA fits BF16 with headroom. vs the production llama.cpp
serving (Gemma 4 26B-A4B Q6_K, turbo4 KV, ai-infer2).

| Dimension | BF16 (vLLM, GX10) | Q6_K (llama.cpp, fleet) | Δ |
|---|---|---|---|
| Knowledge (~370q) | **98.24%** (3-judge Opus-4.8) | 98.56% (multi-judge Opus-4.6) | −0.32 pt* |
| Agentic (30-task) | **88.7%** (266/300, 26/30 verified) | 58.0% (174/300) | +30.7 pt** |
| Loop (24 gens) | **0 spirals** ✅ | 0 spirals ✅ | tie |

\* Knowledge Δ is a **tie within noise** and **judge-confounded**: BF16 scored by
Opus-4.8 (4.6 key dry), Q6_K by the campaign's Opus-4.6. Opus-4.8 judges stricter,
so same-judge BF16 vLLM ≈ Q6_K. Weak spot both ways: scenarios (chunk9, ~91.6%).

\*\* Agentic Δ is **NOT a clean serving comparison — heavy date-confound.** The BF16
vLLM run is 2026-06-27 through vLLM 0.23's unified tool-parser; the llama.cpp 58.0%
is a 2026-06-17 run (older harness/parser era). The +30.7 pt almost certainly
reflects harness + tool-parsing maturity, not BF16-vs-Q6_K. A same-day llama.cpp
re-run is needed to attribute it. Treat 88.7% as "BF16-on-vLLM-0.23 is strong at
agentic", not "vLLM beats llama.cpp by 30 pt."

## Verdict
BF16 on vLLM is a **fully viable serving of the Gemma 4 26B** — knowledge is tied
with the Q6_K llama.cpp fleet serving (within run-spread + judge strictness), loop
resistance is perfect on both, and agentic is strong (88.7%) though not cleanly
comparable to the stale llama.cpp agentic number. No knowledge/quality cost to
serving the 26B on vLLM at BF16; it's a legitimate vLLM option for this model on
the 121 GB GX10. (As with the 122B, this is about *vLLM serving viability*, not a
reason to prefer the 26B over the fleet's 35B-A3B.)

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Agentic: `../../agentic/results/gemma4-26b/agentic-20260627-215341.json`.
Loop: `../../loop-detection/results/gemma4-26b/*-20260627-*-score.json` (24 gens, 0 spirals).
