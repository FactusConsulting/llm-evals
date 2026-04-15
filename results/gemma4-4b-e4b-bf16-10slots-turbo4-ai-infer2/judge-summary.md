# Judge Summary — gemma4-4b-e4b-bf16-10slots-turbo4-ai-infer2

Scored using the `/judge` skill v2 — two parallel Opus 4.6 judges per run, mean(A,B) per question, no super-judge re-scoring (mean(A,B) is the primary stable signal).

## Per-run results

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 722/740 | 97.57% | 354 | 14 | 2 | 76 (20.5%) |
| 2 | 714/740 | 96.49% | 348 | 18 | 4 | 104 (28.1%) |
| 3 | 710/740 | 95.95% | 344 | 22 | 4 | 66 (17.8%) |
| **Mean** | **715.3/740** | **96.67%** | **349** | **18** | **3.3** | **82 (22.1%)** |

Range across runs: **1.62pp**

## Per-judge raw scores

| Run | Judge A | Judge B |
|---|---|---|
| 1 | 97.03% | 95.8% |
| 2 | 95.3% | 95.0% |
| 3 | 94.5% | 96.4% |

Inter-judge agreement: 94-97%. Judge B run1 was slightly more lenient on NET questions; Judge A run3 caught more code-stub partials in chunk 9. Cross-run variance per-judge is ~2.5pp, matching expected single-judge drift.

## Chunk 9 breakdown (scenarios)

| Run | Part A (analysis) | Part B (code) | Part C (design) |
|---|---|---|---|
| 1 | 20/20 (100%) | 11/20 (55%) | 20/20 (100%) |
| 2 | 20/20 (100%) | 12/20 (60%) | 20/20 (100%) |
| 3 | 20/20 (100%) | 10/20 (50%) | 20/20 (100%) |
| **Mean** | **100%** | **55%** | **100%** |

Part A and Part C are perfect — the model is as strong as 26B at analysis and architectural design. Part B (code writing) is the gap: -25pp vs 26B.

## Deterministic Part B validator (syntax-only)

| Run | Valid Part B code blocks | All-valid scenarios |
|---|---|---|
| 1 | 8/10 | SC1, SC3, SC4, SC6, SC7, SC8, SC9, SC10 |
| 2 | 8/10 | SC1, SC3, SC4, SC6, SC7, SC8, SC9, SC10 |
| 3 | 6/10 | SC1, SC3, SC4, SC6, SC8, SC10 |

**The 4B's Part B code validates MORE reliably than the 26B's** (8/10 vs 26B's 5/10 in runs 1-2). But judges rated 4B's Part B *lower* (55% vs 80%).

**Failure mode difference**:
- **26B**: semantically correct code with syntactic errors (invents statement names like `query_string_match` in WAFv2) → validator catches it
- **4B**: syntactically valid code with semantic errors (uses wrong resource type for the question's intent, e.g. `aws_efs_file_system` where a generic NFS CSI driver was asked for) → validator misses, judges catch it

Neither "validator pass" nor "judge pass" alone is sufficient. Both matter.

## Persistent failure modes (same across all 3 runs)

- **N2 subnet math** — wrong network address for /20
- **B7 bash redirection** — wrong ordering semantics (`>file 2>&1` vs `2>&1 >file`)
- **L6 disk full diagnosis** — wrong root cause (doesn't default to deleted-but-open files)
- **SC9-B AWS WAFv2** — semantic errors in statement structure (different flavor from 26B's failure, same category)
- **SC3-B / SC8-B** — stub/skeleton scripts instead of complete implementations

## Comparison vs 26B Q6_K baseline (same /judge v2 methodology)

| Metric | 26B Q6_K | 4B E4B BF16 | Delta |
|---|---|---|---|
| Mean score | 98.56% | 96.67% | **−1.89pp** |
| Range | 0.67pp | 1.62pp | +0.95pp |
| Chunk 9 Part A | ~95% | 100% | **+5pp** |
| Chunk 9 Part B | ~80% | 55% | **−25pp** |
| Chunk 9 Part C | ~100% | 100% | 0pp |
| Parallel slots | 2 | 10 | **5×** |
| Per-slot context | 229k | 131k | −43% |
| VRAM used | ~30 GB | ~18 GB | −40% |

**Net assessment**: 4B is 1.89pp behind 26B overall but offers 5× parallelism with lower VRAM footprint. The entire quality gap is concentrated in Part B (code writing). For workloads that do NOT heavy-lift on Part B, 4B is effectively at parity with 26B.

## Files in this directory

- `run{1,2,3}/chunk{1..9}-response.txt` — raw model output (runs generated in parallel via xargs -P 9)
- `run{1,2,3}/judge.json` — full per-question audit (both judges' ratings + final)
- `judge-summary.md` — this file
- `verdict.md` — production decision + deployment context
- `chunks/` → symlink to `../gemma4-26b-q6k/chunks/`
- `run-chunk.sh` — API wrapper

Plus `loop-detection/results/gemma4-4b-e4b-bf16-10slots-turbo4-ai-infer2-run1/` for the loop-detection scenarios.
