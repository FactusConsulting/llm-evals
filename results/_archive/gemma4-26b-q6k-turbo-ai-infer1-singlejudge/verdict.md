# Verdict — Gemma 4 26B-A4B Q6_K turbo4 (ai-infer1) — single-judge re-run

**Knowledge/reasoning score: 94.1%** (696.0/740, 2-round average; 740 pts / 370 items;
2026-06-09). Generated directly against ai-infer1 `:8001` (26B-A4B **Q6_K**, model file
22.85 GB), judged with the verbatim `judge-knowledge.py` rubric (pass=2 / partial=1 /
fail=0) by Opus subagents, 2 independent rounds averaged.

**Why a re-run:** ai-infer1's canonical 26B verdict is **98.56%** under the historical
**6-judge** harness. This re-run exists only to put 26B on the SAME single-judge × 2-round
scale as the Q4 (ai3) and Q8 (ai2) runs, so the three are directly comparable. Do NOT
read 94.1% as a regression — it is the stricter single-judge scale (the SAME responses
the 6-judge harness would score ~98%).

## Per-chunk (2-round avg)

| Chunk | Topic | Score | rounds |
| :-- | :-- | --: | :-- |
| 1 | networking / linux | 77.5/80 (96.9%) | 78/77 |
| 2 | k8s / dev | 78.0/80 (97.5%) | 78/78 |
| 3 | opentofu / ansible | 76.0/80 (95.0%) | 77/75 |
| 4 | go / rust | 78.5/80 (98.1%) | 80/77 |
| 5 | .net / python | 74.0/80 (92.5%) | 74/74 |
| 6 | js / bash / powershell | 110.0/120 (91.7%) | 105/115 |
| 7 | app-arch / on-prem | 76.5/80 (95.6%) | 78/75 |
| 8 | cloud / OT | 77.0/80 (96.2%) | 78/76 |
| 9 | **scenarios (A/B/C)** | **48.5/60 (80.8%)** | 48/49 |
| **knowledge prose (1–8)** | | **647.5/680 (95.2%)** | |
| **TOTAL** | | **696.0/740 (94.1%)** | |

## Profile

Best of the three, and the gap is concentrated where it matters: **chunk-9 scenarios
80.8%** vs ~69–71% for both 12 Bs — the bigger model writes more genuinely-runnable code
for the hardest multi-part Part-B tasks. On plain prose (95.2%) it leads the 12 Bs by
only ~1–4 pts. Run-to-run variance near zero (696/696).

See [`../12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md`](../12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md).
26B stays the knowledge/planning model.
