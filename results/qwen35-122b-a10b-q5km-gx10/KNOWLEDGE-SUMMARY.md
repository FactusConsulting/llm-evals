# Qwen3.5-122B-A10B Q5_K_M (GX10) — Knowledge eval
6-judge (Opus, 2/run x 3 runs), 370 questions/run.
| Run | A | B | Mean |
|---|---|---|---|
| run1 | 98.8% | 99.2% | 99.00% |
| run2 | 98.0% | 99.5% | 98.75% |
| run3 | 98.8% | 99.2% | 99.00% |

**Overall: 98.92%** (spread 98.0-99.5, stdev 0.48)
vs Qwen3.6-35B-A3B BF16 98.65% -> +0.27pt (within noise). The 122B does NOT meaningfully beat the 3.5x-smaller 35B-A3B on knowledge.
