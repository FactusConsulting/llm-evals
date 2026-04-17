# Model Evaluation Summary

Last updated: 2026-04-17

## Current Production Models

| Model | Host | Config | Score | % | Eval Method | Slots | Context |
|-------|------|--------|-------|---|-------------|-------|---------|
| **Gemma 4 26B A4B Q6_K** | ai-infer1 | turbo4 KV + Q8_0 mmproj | **730/740** | **98.56%** | /judge v2 (3 runs, 2× Opus judges) | 2 | 2×229k |
| **Gemma 4 E4B BF16 (4B)** | ai-infer2 | turbo4 KV + F32 mmproj | **715/740** | **96.67%** | /judge v2 (3 runs, 2× Opus judges) | 10 | 10×131k |

**Delta**: −1.89pp. The 4B scores 96.67% with 5× the parallelism. Gap is concentrated in chunk 9 Part B (code writing: 55% vs 80%).

**Agent routing**: Prompt-heavy agents (lead-dev, architect, pentester) → 26B. Parallelism-heavy agents (ops-agent, alfred, pm, qa) → 4B. Cross-server fallback.

---

## All Gemma 4 Variants Tested

| Model | Quant | KV | Context | Slots | Score | % | Eval | Decision |
|-------|-------|-----|---------|-------|-------|---|------|----------|
| 26B A4B Q6_K (v2) | Q6_K | turbo4 | 2×229k | 2 | 730/740 | 98.56% | /judge v2 | **Production (ai-infer1)** |
| E4B BF16 (4B) | BF16 | turbo4 | 10×131k | 10 | 715/740 | 96.67% | /judge v2 | **Production (ai-infer2)** |
| 26B A4B Q5_K_L | Q5_K_L | turbo4 | 2×262k | 2 | — | — | Part B regression | **Rejected** (−15pp Part B vs Q6_K) |
| 31B Q4_K_M | Q4_K_M | turbo4 | 1×256k | 1 | 373/385 | 96.97% | ad-hoc Opus | **Rejected** (no improvement over 26B, worse Part B) |
| 31B Q5_K_M | Q5_K_M | turbo4 | 1×160k | 1 | 374/385 | 97.08% | ad-hoc Opus | **Rejected** (same — model architecture limit) |
| E4B Q6_K_L (early) | Q6_K_L | q4_0 | 2×65k | 2 | 654/700† | 93.4% | ad-hoc Opus | Superseded by BF16 config |

†Early 4B eval used 350 questions (40 fewer scenario sub-questions).

## Rejected Variants — Why

### 26B Q5_K_L (2026-04-14)
Tested to see if smaller weights (19.8 GB vs 21.6 GB) could buy more context. Result: **Part B (code writing) regressed by 15 percentage points** vs Q6_K. The context gain (524k vs 458k) wasn't worth the quality loss. Q6_K is the right quant for 26B.

### 31B Q4_K_M + Q5_K_M (2026-04-14)
Tested to see if 31B's extra parameters improve over 26B. Both quants scored within noise of 26B (96.97-97.08% vs 96.36%). **Part B code writing was WORSE** (65-67% vs 73%) — same broken AWS provider DSL, incomplete Terraform scaffolding, thin Ansible playbooks. This is a model-architecture issue, not quantization. **Do not invest in bigger GPUs for 31B.**

---

## Gemma 4 26B Q6_K v2 — Detailed (Production)

**Date**: 2026-04-15 | **Host**: ai-infer2 (eval), ai-infer1 (prod sibling)

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 726/740 | 98.11% | 357 | 12 | 1 | 49 (13.2%) |
| 2 | 731/740 | 98.78% | 362 | 7 | 1 | 49 (13.2%) |
| 3 | 731/740 | 98.78% | 361 | 9 | 0 | 64 (17.3%) |
| **Mean** | **730/740** | **98.56%** | **360** | **9** | **0.7** | **54** |

Run-to-run range: 0.67pp. Inter-judge agreement: 96.8-97.8%.

### Per-chunk scores (mean)

| Chunk | Topic | % |
|---|---|---|
| 1 | Networking + Linux | ~98% |
| 2 | Kubernetes + Dev | ~99% |
| 3 | OpenTofu + Ansible | ~97% |
| 4 | Go + Rust | ~99% |
| 5 | .NET + Python | ~99% |
| 6 | JS + Bash + PowerShell | ~98% |
| 7 | App Architecture | ~99% |
| 8 | On-Prem + Cloud + OT | ~99% |
| 9 | Scenarios (Part A/B/C) | ~97% |

### Loop detection (chunk 9, 12 scenarios)
New template (b8753): spiraling visible in LD1, LD4 (were hidden by tool-call short-circuit on old template). Not critical — scenarios complete within timeout.

---

## Gemma 4 E4B BF16 (4B) — Detailed (Production)

**Date**: 2026-04-15 | **Host**: ai-infer2

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 722/740 | 97.57% | 354 | 14 | 2 | 76 (20.5%) |
| 2 | 714/740 | 96.49% | 348 | 18 | 4 | 104 (28.1%) |
| 3 | 710/740 | 95.95% | 344 | 22 | 4 | 66 (17.8%) |
| **Mean** | **715/740** | **96.67%** | **349** | **18** | **3.3** | **82 (22.1%)** |

Run-to-run range: 1.62pp. `alt_acceptable` rate 22.1% — 4B solves problems differently but correctly.

### Per-chunk scores (mean)

| Chunk | Topic | % | vs 26B |
|---|---|---|---|
| 1 | Networking + Linux | ~96% | −2pp |
| 2 | Kubernetes + Dev | ~97% | −2pp |
| 3 | OpenTofu + Ansible | ~94% | −3pp |
| 4 | Go + Rust | ~98% | −1pp |
| 5 | .NET + Python | ~97% | −2pp |
| 6 | JS + Bash + PowerShell | ~96% | −2pp |
| 7 | AppArch + OnPrem | ~97% | −2pp |
| 8 | Cloud + OT | ~97% | −2pp |
| 9 | Scenarios (A/B/C) | ~95% | −2pp (Part B: 55% vs 80%) |

### Loop detection
No dramatic spirals. LD9 borderline ambiguous-stopping case. Same pattern as 26B.

### Throughput
- Per-slot: ~30 tok/s under parallel load
- Aggregate: ~300 tok/s across 10 slots
- Parallel efficiency: 81%

---

## Historical Models (Qwen 3.5 era, pre-Gemma 4)

| Model | Config | Score | % | Notes |
|-------|--------|-------|---|-------|
| Qwen3.5-27B Opus Distilled Q4_K_M | 1×131k q4_0 | 240/240 | 100% | Partial (3/9 chunks), thinking-mode degenerate |
| Qwen3.5-9B Q8_0 | 2×131k q4_0 | 708/740 | 95.7% | Dense 9B, best Qwen variant |
| Qwen3.5-35B-A3B Q5_K_M | 2×60k q4_0 | 691/740 | 93.4% | Best MoE config |
| Qwen3.5-35B-A3B Q5_K_M | 2×131k q8_0 | 689/740 | 93.1% | |
| Qwen3.5-35B-A3B Q5_K_M | 1×262k q8_0 | 683/740 | 92.3% | |
| Qwen3.5-35B-A3B Q5_K_M | 2×262k q4_0 | 668/740 | 90.3% | |
| Qwen3.5-35B-A3B Q5_K_M | 3×131k q4_0 | 658/740 | 88.9% | 3-slot GPU contention |

## Key Findings (All-Time)

1. **Gemma 4 26B Q6_K is the best model tested** — 98.56% with 2 parallel slots
2. **Gemma 4 4B is remarkably capable** — 96.67% at 5× the parallelism of 26B
3. **TurboQuant KV (turbo4) has no quality penalty** — ~q8_0 quality at q4_0 footprint
4. **31B does not beat 26B** — model architecture limit on code writing, not precision
5. **Q5_K_L degrades Part B** — Q6_K is the sweet spot for 26B
6. **4B's gap is in code writing** — Part B chunk 9: 55% vs 80%. Everything else is within 2-3pp
7. **Qwen 3.5 era peaked at 95.7%** (9B dense) — Gemma 4 26B is +2.9pp better
8. **Loop detection**: 4B has 0 spirals, 26B has occasional spirals on ambiguous scenarios

## Evaluation Methodology

**Current (/judge v2)**: Two parallel Claude Opus 4.6 judges score each run independently. Final score = mean(Judge A, Judge B) per question. `alternative_acceptable` flag credits valid non-reference approaches (target rate 10-30%). Deterministic Part B validators (shellcheck, terraform fmt, py_compile, jq, yaml.safe_load) supplement judge scoring.

**Historical (ad-hoc Opus)**: Single Opus judge per run, no structured rubric. Higher variance (2.43pp vs 0.67pp for /judge v2). Historical scores are comparable within their cohort but not directly to /judge v2 scores.

## Detailed Results

See model-specific subdirectories for per-question JSON, raw responses, and judge output.
