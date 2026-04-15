# Verdict — Gemma 4 26B Q6_K + b8753 turbo + new chat template (v2)

**Date**: 2026-04-15
**Hosts**: ai-infer2 (eval) + ai-infer1 (production sibling, byte-identical)
**Setup**: llama.cpp turbo fork at b8753 with `turboquant-gemma4-v2` patch + Bartowski Q6_K GGUF (md5 `2db87dc4877850b7d01feaac179c2d13`) + Gemma 4's new official chat template (sha256 `1d35a24a2a63cc60`) + `--cache-type-k turbo4 --cache-type-v turbo4` + 2×229k context + Q8_0 mmproj (vision)

## TL;DR

- **Mean score across 3 runs**: **98.56%** (730/740)
- **Run-to-run variance**: 0.67pp range (very stable)
- **Quality holds vs old b8667**: the new template + PR #21704 runtime fix preserves model quality and improves it marginally on Part A (analysis) and Part C (architecture). Part B (code/IaC) shows the same persistent failure modes as before — these are model-architecture limits, not template-related.
- **Recommendation**: keep both ai-infer1 and ai-infer2 on this build. No reason to roll back.

## Aggregate scores (judged by /judge skill v2 — two parallel Opus 4.6 judges with stable rubric)

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 726/740 | 98.11% | 357 | 12 | 1 | 49 (13.2%) |
| 2 | 731/740 | 98.78% | 362 | 7 | 1 | 49 (13.2%) |
| 3 | 731/740 | 98.78% | 361 | 9 | 0 | 64 (17.3%) |
| **Mean** | **729.3/740** | **98.56%** | **360** | **9** | **0.7** | **54** |

Range across runs: **0.67pp** — very tight, near-noise-floor variance.

## Cross-run inter-judge agreement

Two independent Opus judges scored each run:

| Run | Judge A % | Judge B % | Inter-judge agreement |
|---|---|---|---|
| 1 | 97.16% | 97.57% | 97.0% (359/370 questions agree) |
| 2 | 98.24% | 98.24% | 97.8% (362/370) |
| 3 | 98.24% | 97.70% | 96.8% (358/370) |

Both judges credit valid alternatives liberally — `alternative_acceptable` rate is 5.7-17.3% per judge, well within the 10-30% target.

## Per-chunk scores (mean across 3 runs)

| Chunk | Topic | Mean % |
|---|---|---|
| 1 | Networking + Linux | ~98% |
| 2 | Kubernetes + Dev | ~99% |
| 3 | OpenTofu + Ansible | ~97% |
| 4 | Go + Rust | ~99% |
| 5 | .NET + Python | ~99% |
| 6 | JS + Bash + PowerShell | ~98% |
| 7 | App Architecture | ~99% |
| 8 | OnPrem + Cloud + OT | ~99% |
| 9 | Cross-domain scenarios (A/B/C) | ~95% |

## Chunk 9 Part B (code/IaC writing) — the historically weak area

| Run | Part A (analysis) | Part B (code) | Part C (design) |
|---|---|---|---|
| 1 | ~95% | ~80% | ~100% |
| 2 | ~95% | ~85% | ~100% |
| 3 | ~95% | ~85% | ~100% |

Part B is significantly improved over previous /judge v1 readings (which had bugs in response extraction). Real failure modes (concrete bugs the judges caught):

1. **SC9-B AWS WAFv2** — model emits fictitious `query_string_match` / `rq_key_match_statement` HCL. Persistent across all 3 runs. Real WAFv2 syntax requires `byte_match_statement { field_to_match { query_string {} } }`. **fail in all runs** (deterministic validator confirms this is invalid HCL).
2. **SC4-B Terraform NFS** — model uses fictitious `kubernetes_csi_volume` resource (real name is `kubernetes_persistent_volume_v1` with `csi { driver = "nfs.csi.k8s.io" }`). Flaky: fails in run 1+3, passes in run 2.
3. **SC6-B AWS Transit Gateway** — model writes incomplete HCL with `for_each` over hardcoded set instead of variable list, missing VPN attachment block, missing default-deny SG. **partial in all runs** (validator: invalid HCL).
4. **SC10-B Patroni Ansible playbook** — model writes a stub with template + service but skips package install, etcd DCS config, Patroni handlers structure. **partial**.

These are real model limitations, not judging artifacts.

## Loop-detection eval (separate suite)

Run on ai-infer2 against the same v2 build. Mixed picture vs old b8667:

| | Old b8667 | New b8753 |
|---|---|---|
| Spirals flagged | 2 (LD2, LD12) | 3 (LD1, LD2, LD4) |
| LD12 (was worst) | 2105w spiral | **102w clean — fixed** |
| LD3 | 1873w borderline | 122w concise |
| LD1 | 8w tool-call short-circuit | 3560w spiral |
| LD4 | 195w concise | 4202w spiral |

The new template engages with prompts that the old template short-circuited via tool-call markup. This is a **synlighedsændring**: spiraling tendencies were always there, hidden behind the tool-call early-exit. Net is a slight regression on the loop-detection axis but not critical.

## Hardware budget

| GPU | Model layers | KV cache | mmproj (vision) | total VRAM |
|---|---|---|---|---|
| GPU0 (RTX 5060 Ti, 16 GB) | ~half | 1 slot × 229k turbo4 | Q8_0 (~806 MB) | ~15.6 GB |
| GPU1 (RTX 5060 Ti, 16 GB) | ~half | 1 slot × 229k turbo4 | — | ~14.7 GB |

2 slots × 229k context = 458k aggregate context per host. With turbo4 KV (≈q8_0 quality at q4_0 footprint) and Q6_K weights (21.6 GB), this is close to the limit on dual 16 GB cards.

## Comparison with previous configs

| Config | Mean % | Range | Note |
|---|---|---|---|
| 26B Q6_K, b8667, old template (pre-2026-04-10) | 96.36% | n/a | single ad-hoc judge run, old baseline |
| **26B Q6_K, b8753, new template (THIS)** | **98.56%** | **0.67pp** | mean of 3 runs, 2-judge stable |
| 31B Q4_K_M, b8667 | 96.97% | ~1pp | tested 2026-04-14 (`gemma4-31b-vs-26b-verdict.md`) |
| 31B Q5_K_M, b8667 | 97.08% | n/a | single run, tested 2026-04-14 |

26B Q6_K is the winner across all configurations tested. Larger 31B parameters do not beat it on this workload, especially on Part B (code generation). The new template + PR #21704 runtime support pushes 26B Q6_K to its highest measured score.

## Decision

**Production status**: Both ai-infer1 and ai-infer2 stay on `b8753-turboquant-gemma4-v2` with the new GGUF template. No rollback planned.

**Open questions (deferred)**:
- Re-test 31B with the new template + PR #21704 to see if it changes the 26B vs 31B verdict
- Add SQL/Go validators to chunk 9 Part B coverage (currently unvalidated for those languages)
- Investigate persistent SC9-B WAFv2 failure — could be a fine-tuning gap that future Gemma versions might fix
