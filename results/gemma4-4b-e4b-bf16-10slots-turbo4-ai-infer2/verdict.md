# Verdict — Gemma 4 E4B BF16 + F32 mmproj + turbo4 KV + 10 slots (4B model)

**Date**: 2026-04-15
**Host**: ai-infer2
**Setup**: llama.cpp turbo fork at b8753 with `turboquant-gemma4-v2` patch + unsloth/gemma-4-E4B-it BF16 weights (15 GB) + F32 mmproj vision (1.9 GB) + `--cache-type-k turbo4 --cache-type-v turbo4` + 10 parallel slots × 131072 native context (1,310,720 total aggregate context) + new official Gemma 4 chat template

## TL;DR

- **Mean score across 3 runs**: **96.67%** (715.3/740)
- **Run-to-run variance**: 1.62pp range
- **Delta vs 26B Q6_K baseline**: **−1.89pp** (96.67% vs 98.56%)
- **Hardware value**: 10 parallel slots = 5× the parallelism of 26B (2 slots × 229k ctx)
- **Recommendation**: keep as the parallelism-heavy sibling to 26B. Use 4B for many concurrent agent sessions; use 26B for prompt-heavy or code-heavy single-agent sessions.

## Aggregate scores (/judge skill v2 — two parallel Opus 4.6 judges)

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 722/740 | 97.57% | 354 | 14 | 2 | 76 (20.5%) |
| 2 | 714/740 | 96.49% | 348 | 18 | 4 | 104 (28.1%) |
| 3 | 710/740 | 95.95% | 344 | 22 | 4 | 66 (17.8%) |
| **Mean** | **715.3/740** | **96.67%** | **349** | **18** | **3.3** | **82 (22.1%)** |

Range across runs: **1.62pp** — higher than 26B (0.67pp) but still well within noise floor for a 3-run eval.

**Very high `alternative_acceptable` rate (22.1%)** — the 4B model frequently solves problems with a different approach than the reference, and judges correctly credit those as valid. This is a healthy pattern.

## Per-judge raw scores

| Run | Judge A | Judge B |
|---|---|---|
| 1 | 97.03% | 95.8% |
| 2 | 95.3% | 95.0% |
| 3 | 94.5% | 96.4% |

Inter-judge agreement: 94-97% per run. A bit lower than 26B (96-98%) — 4B's more verbose and less canonical responses trigger more borderline calls. Super-judge resolution not run (mean(A,B) gives stable final score).

## Per-chunk scores (mean across 3 runs)

| Chunk | Topic | Mean % |
|---|---|---|
| 1 | Networking + Linux | ~96% |
| 2 | Kubernetes + Dev | ~97% |
| 3 | OpenTofu + Ansible | ~94% |
| 4 | Go + Rust | ~98% |
| 5 | .NET + Python | ~97% |
| 6 | JS + Bash + PowerShell | ~96% |
| 7 | AppArch + OnPrem | ~97% |
| 8 | OnPrem + Cloud + OT | ~98% |
| 9 | Cross-domain scenarios | ~85% |

Chunk 9 is the biggest deficit vs 26B. All other chunks are within 2pp of 26B.

## Chunk 9 Part A/B/C breakdown

| Run | Part A (analysis) | Part B (code/IaC) | Part C (design) |
|---|---|---|---|
| 1 | **100%** | 55% | **100%** |
| 2 | **100%** | 60% | **100%** |
| 3 | **100%** | 50% | **100%** |
| **Mean** | **100%** | **55%** | **100%** |

**Part A + Part C are perfect** — the 4B is as good as the 26B at analysis and architectural design for scenarios.

**Part B is the gap** — 55% vs 26B's ~80%. This is where the model-size difference shows up: code writing for complex IaC requires detailed knowledge of specific API surfaces, resource types, and exact syntax that smaller models don't retain as reliably.

## Interesting wrinkle — validator vs judges disagree on Part B

Deterministic syntax validator (`terraform fmt -check`, `shellcheck`, etc.) results:

| Run | Valid Part B blocks | 26B v2 comparison |
|---|---|---|
| 1 | 8/10 | 26B run 1: 5/10 |
| 2 | 8/10 | 26B run 2: 6/10 |
| 3 | 6/10 | 26B run 3: 5/10 |

**The 4B's Part B code validates MORE reliably than the 26B's.** But judges scored 4B's Part B *lower* (55%) than 26B's (80%). Why?

Two different failure modes:

| | 26B Part B failures | 4B Part B failures |
|---|---|---|
| Style | Semantically correct, syntactically broken | Syntactically valid, semantically wrong |
| Example | Real `aws_wafv2_web_acl` resource, but invents statement names like `query_string_match` | Writes valid HCL but uses wrong approach (e.g. `aws_efs_file_system` where question asked for NFS on generic provider) |
| Validator catches? | Yes (fails HCL syntax check) | No (compiles fine) |
| Judge catches? | Yes | Yes |

**Implication**: neither "validator-valid" nor "judge-passing" is sufficient alone. 26B fails validator more; 4B fails judges more. Both end up at ~55-80% Part B.

## Persistent failure modes across all 3 runs

From judge outputs:
1. **N2** — 4B calculates wrong network address for /20 subnet (reference is 10.0.0.0, model produces wrong value). Off in all 3 runs.
2. **B7** — wrong bash redirection order (`>file 2>&1` vs `2>&1 >file` semantics).
3. **L6** — wrong root cause for "df 100% but du shows less" (deleted-but-open files is the real answer; model often gives a different plausible cause).
4. **SC9-B** — AWS WAFv2 Terraform with semantically incorrect statement structure in all 3 runs (same persistent failure mode as 26B but with different flavor — 4B writes valid HCL using wrong resource shapes).
5. **SC3-B / SC8-B** — Chunk 9 script questions with stub/skeleton implementations instead of complete code.

## Hardware performance (measured during eval)

- **Parallelism**: 10 slots active (9 for knowledge eval + 1 for loop-detection in early runs)
- **Per-slot throughput**: ~30 tok/s (under parallel load)
- **Aggregate throughput**: ~300 tok/s across all slots
- **Parallel efficiency**: 81% (vs theoretical 37 tok/s × 10 = 370 tok/s single-slot scaling)
- **GPU utilization (nvidia-smi)**: 40-50% per GPU — normal for small models on dual-GPU tensor-split
- **Memory usage**: GPU 0 = 10.6 GB / 16 GB, GPU 1 = 7.6 GB / 16 GB, 14 GB total headroom

**Response verbosity**: 4B generates ~3× more tokens per response than 26B (658 lines for chunk 6 vs 26B's ~150). Native enable_thinking behavior + smaller model compensating with verbose reasoning. This is why parallel 4B isn't 10× faster than sequential 26B despite more slots.

## Loop-detection eval

Ran alongside knowledge eval with 1 slot. Results under `loop-detection/results/gemma4-4b-e4b-bf16-10slots-turbo4-ai-infer2-run1/`. Pattern similar to 26B — no dramatic spirals, most scenarios handled correctly, LD9 remains the borderline ambiguous-stopping case.

## Comparison vs production alternatives

| Model | Mean | Range | Slots | Ctx/slot | Use case |
|---|---|---|---|---|---|
| 26B Q6_K (ai-infer1) | 98.56% | 0.67pp | 2 | 229k | Single prompt-heavy, long-context agents |
| **4B E4B BF16 (ai-infer2)** | **96.67%** | **1.62pp** | **10** | **131k** | **Many concurrent lightweight agents** |
| 31B Q4_K_M / Q5_K_M (older) | ~97.0% | ~1.1pp | 1 | 256k | Rejected — doesn't beat 26B on Part B |

## Decision

**Production split**:
- **ai-infer1 (26B Q6_K)**: prompt-heavy agents (lead-dev, architect, pentester, alfred) that need deep reasoning, Part B code generation, long single-session context. High quality ceiling (98.56%).
- **ai-infer2 (4B E4B BF16)**: parallelism-heavy workloads (ops-agent, pm, qa) that serve many concurrent lightweight requests. Quality floor 96.67% is still very high and the 5× parallelism is real value.

**Not recommended**: don't replace 26B with 4B for critical code-generation workloads (Part B gap of 25pp matters). Don't replace 4B with 26B for high-concurrency openclaw routing (parallelism matters more than the 2pp quality gap).

**Open questions (deferred)**:
- Re-test 4B at Q8_0 to see if it loses any quality vs BF16 (unlikely — Q8_0 is "effectively lossless" — but would free more headroom)
- Evaluate whether 4B at native 131k is worth sacrificing for larger-but-scaled context (probably not — small models degrade quickly under RoPE scaling)
- Cross-judge with a second vendor (GPT-5 or Gemini 3) to catch any systematic Opus bias
