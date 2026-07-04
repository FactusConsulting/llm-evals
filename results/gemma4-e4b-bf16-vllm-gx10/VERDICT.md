# Gemma 4 E4B BF16 (vLLM, GX10) — full evaluation

Served via vLLM `v0.23.0-aarch64-cu129`, BF16, gemma4 reasoning + tool-call parsers,
gpu-mem-util 0.85, ngram spec-decode. E4B (~4B effective, elastic/MatFormer) is tiny
(15 GB) — fits anywhere.

| Dimension | BF16 (vLLM, GX10) | BF16 (llama.cpp) | Δ |
|---|---|---|---|
| Knowledge (~370q) | **96.08%** (3-judge Opus-4.8) | 96.67% | tie* |
| Agentic (30-task) | **67.7%** (203/300, 19/30 verified) | 86.0% (86/100) | **−18.3 pt** ⚠️ |
| Loop (24 gens) | **0 spirals** ✅ | 0 spirals ✅ | tie |

\* Knowledge: tie within judge-method noise — no cost to serving E4B on vLLM for Q&A.

## The agentic gap is real (and the one negative finding so far)
E4B agentic is **18 pt lower on vLLM** than llama.cpp — the *opposite* direction from
every larger model in this campaign, and **not** a date-confound (the llama.cpp 86.0% is
an *older* 2026-04-15 run; an older harness would bias it down, yet it's higher). The
likely cause is **E4B's elastic/centroid-head architecture**: the homelab llama.cpp E4B
runs on a dedicated AtomicBot fork tuned for the centroid head, while vLLM's generic
Gemma4 path serves the weights but its tool-calling/agentic behaviour for E4B degrades
(19/30 tasks verified vs llama.cpp's stronger pass rate). Knowledge and loop are unaffected.

## Verdict
For **knowledge/reasoning**, E4B on vLLM BF16 is a full-quality serving (tie with llama.cpp,
0 loop spirals) — impressive for a 4B. For **agentic tool-use, prefer the llama.cpp serving**
of E4B: vLLM loses ~18 pt, the campaign's first clear case where vLLM does NOT match llama.cpp
on the same model. Net: E4B-on-vLLM is fine for Q&A, weaker for tools.

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Agentic: `../../agentic/results/gemma4-e4b/agentic-20260628-182220.json`.
Loop: `../../loop-detection/results/gemma4-e4b/*-20260628-*-score.json` (24 gens, 0 spirals).
