# Gemma 4 12B BF16 (GX10, vLLM) — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. Served via vLLM
`v0.23.0-aarch64-cu129` BF16 (`gemma4-12b`, `--dtype bfloat16 --reasoning-parser
gemma4 --tool-call-parser gemma4`, ngram spec-decode).

| Run | Pass A | Mean |
|---|---|---|
| run1 | 97.57% | 97.57% |
| run2 | 97.16% | 97.16% |
| run3 | 96.49% | 96.49% |

**Overall: 97.07%** (2155/2220; spread 96.49–97.57, stdev ~0.45)

Per-chunk (mean across runs): chunks 1–8 = 95–100%; **chunk9 (scenarios) = ~80%**
(83.3 / 80.0 / 76.7) — the consistent weak spot, multi-step scenario reasoning.

## The 12B quant ladder (knowledge)
Same model, three precisions — this is the clean story:

| Precision | Engine | Knowledge | Δ vs BF16 |
|---|---|---|---|
| **BF16** | vLLM (GX10) | **97.07%** | — (this run) |
| **BF16** | llama.cpp (ai-infer2, archived) | 97.95% | — (engine tie) |
| **Q8_0** | llama.cpp (ai-infer2) | 92.1% | **−5 pt** |
| **Q4** | llama.cpp (ai-infer3, fleet overflow) | 89.9% | **−7 pt** |

Gemma 4 12B is **unusually quant-sensitive**: Q8 already costs ~5 pt vs BF16, Q4 ~7 pt.
And that's a *conservative* gap — the BF16 number was scored by the stricter Opus-4.8
judges, while Q8/Q4 used Opus-4.6, so the true BF16-over-quant lead is if anything larger.

## vLLM vs llama.cpp (engine, same BF16 precision)
BF16 vLLM **97.07%** vs BF16 llama.cpp **97.95%** = −0.88 pt — a **tie** within judge-method
(vLLM scored Opus-4.8, archive scored 6-judge Opus-4.6). No engine penalty; the big gains
over the Q4/Q8 fleet serving are **precision**, not engine.

Raw per-question ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
