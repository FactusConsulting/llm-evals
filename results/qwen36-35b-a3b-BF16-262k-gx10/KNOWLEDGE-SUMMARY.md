# Qwen3.6-35B-A3B BF16 (GX10) — Knowledge eval

6-judge (Opus, 2/run × 3 runs), 370 questions/run.

| Run | Judge A | Judge B | Mean |
|---|---|---|---|
| run1 | 98.5% | 98.6% | 98.55% |
| run2 | 99.5% | 97.8% | 98.65% |
| run3 | 98.9% | 98.6% | 98.75% |

**Overall: 98.65%** (spread 97.8–99.5, stdev 0.51)

vs Q5-stock fleet 97.4% → +1.25pt, within single-judge noise (~4pt).
Verdict: BF16 confirms Q5 knowledge level — no quant regression.
