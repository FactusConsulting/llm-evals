# Verdict — Gemma 4 12B Q8_0 turbo4 (ai-infer2)

**Knowledge/reasoning score: 92.1%** (681.5/740, 2-round average; 740 pts / 370 items;
2026-06-09). Generated directly against ai-infer2 `:8001` (12B **Q8_0**, model file
12.65 GB confirms Q8, 4×262144 native), judged with the verbatim `judge-knowledge.py`
rubric (pass=2 / partial=1 / fail=0) by Opus subagents, 2 independent rounds averaged.

## Per-chunk (2-round avg)

| Chunk | Topic | Score | rounds |
| :-- | :-- | --: | :-- |
| 1 | networking / linux | 77.0/80 (96.2%) | 77/77 |
| 2 | k8s / dev | 78.0/80 (97.5%) | 78/78 |
| 3 | opentofu / ansible | 75.0/80 (93.8%) | 76/74 |
| 4 | go / rust | 76.5/80 (95.6%) | 77/76 |
| 5 | .net / python | 78.0/80 (97.5%) | 78/78 |
| 6 | js / bash / powershell | 100.0/120 (83.3%) | 102/98 |
| 7 | app-arch / on-prem | 78.0/80 (97.5%) | 78/78 |
| 8 | cloud / OT | 78.0/80 (97.5%) | 76/80 |
| 9 | **scenarios (A/B/C)** | **41.0/60 (68.3%)** | 39/43 |
| **knowledge prose (1–8)** | | **640.5/680 (94.2%)** | |
| **TOTAL** | | **681.5/740 (92.1%)** | |

## Profile

Strong, very stable: the 2 judge rounds landed 681/682 — essentially zero
run-to-run variance, meaning Q8's answers are decisively correct (judges agree).
Prose knowledge 94.2%; the only weak spot is the chunk-9 scenario Part-B
"write runnable code" tasks (the documented 12B-family trait), and chunk 6
(js/bash/ps, 60 items — the most nit-picked syntax chunk).

## Comparison

This number is from the **same single-judge × 2-round session** as the Q4 (ai3,
89.9%) and 26B (ai1, 94.1%) re-runs — see
[`../12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md`](../12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md).
Q8 sits ~2 pts above Q4 and ~2 pts below 26B. NOT comparable to the historical
6-judge references (this method runs ~4–5 pts stricter). Q8 is the agentic default.
