# Gemma 4 12B BF16 (vLLM, GX10) — full evaluation

Served via vLLM `v0.23.0-aarch64-cu129`, BF16, `--reasoning-parser gemma4
--enable-auto-tool-choice --tool-call-parser gemma4`, gpu-mem-util 0.85, ngram
spec-decode. The full-precision 12B (~24 GB) only fits the 121 GB GX10 — the 16 GB
fleet GPUs must quantize it (why the fleet ran Q4/Q8).

| Dimension | BF16 (vLLM, GX10) | Best llama.cpp | Δ |
|---|---|---|---|
| Knowledge (~370q) | **97.07%** (3-judge Opus-4.8) | 97.95% BF16 / 92.1% Q8 / 89.9% Q4 | tie vs BF16* |
| Agentic (30-task) | **77.3%** (232/300, 24/30 verified) | 65.0% (195/300, Q4) | +12.3 pt** |
| Loop (24 gens) | **0 spirals** ✅ | 0 spirals ✅ | tie |

\* Knowledge: BF16 vLLM ≈ BF16 llama.cpp (97.07 vs 97.95, judge-method noise). The
real story is the **quant ladder** — BF16 beats Q8 by ~5 pt and Q4 by ~7 pt (Gemma 12B
is quant-sensitive). See KNOWLEDGE-SUMMARY.md.

\*\* Agentic Δ vs the Q4 fleet serving conflates **precision + engine + harness era**
(the 65.0% Q4 run predates vLLM 0.23's unified tool-parser). Not a clean attribution;
treat 77.3% as "BF16-on-vLLM-0.23 is solid", not "+12 pt from vLLM".

## Verdict
BF16 on vLLM serves the Gemma 4 12B at **full quality** — knowledge tied with BF16
llama.cpp, 0 loop spirals, solid agentic. The headline finding is the **quant ladder**:
the fleet's Q4/Q8 serving leaves ~5–7 knowledge pt on the table vs BF16, and BF16 only
fits on the 121 GB GX10. So vLLM/GX10 is the way to run the 12B at full strength — but
the 12B is currently retired from the fleet (production is qwen3.6-35b), so this is a
capability data point, not a fleet change. No engine penalty for vLLM.

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Agentic: `../../agentic/results/gemma4-12b/agentic-20260628-145648.json`.
Loop: `../../loop-detection/results/gemma4-12b/*-20260628-*-score.json` (24 gens, 0 spirals).
