# Qwen3.6-27B BF16 (GX10) — Knowledge eval

6-judge (Opus, 2/run × 3 runs), 370 questions/run. Per-judge % recomputed from raw
per-question ratings (pass=2/partial=1/fail=0); two subagents miscounted their own
`totals` (run2-A, run3-B) so the rating maps are authoritative.

| Run | Judge A | Judge B | Mean |
|---|---|---|---|
| run1 | 98.92% | 99.32% | 99.12% |
| run2 | 98.78% | 98.92% | 98.85% |
| run3 | 99.59% | 98.78% | 99.19% |

**Overall: 99.05%** (spread 98.78–99.59, stdev 0.30)

Dense 27B BF16 is the single slowest model on the GX10 (~4.6 tok/s). On knowledge it
edges every other candidate — but every model lands inside a 0.4pt band, well within
single-judge noise (~4pt). Knowledge is saturated; it does not differentiate the field.
The differentiator is agentic + throughput, where the MoE 35B-A3B wins decisively.
