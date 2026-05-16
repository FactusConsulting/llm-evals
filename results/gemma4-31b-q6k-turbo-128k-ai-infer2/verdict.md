# Verdict — Gemma 4 31B Q6_K + turbo4, single-slot 128k ctx (ai-infer2)

**Date**: 2026-05-16
**Host**: ai-infer2 (192.168.2.171), 2×16 GB RTX 5060 Ti
**Setup**: `bartowski/google_gemma-4-31B-it-GGUF` **Q6_K** (dense 31B, ~25.5 GB) + llama.cpp turbo fork + **turbo4 KV** + **single slot × 131072 (128k) ctx** + interleaved jinja, thinking on, vision off. Profile `ansible/inventory/model_profiles/gemma4-31b-q6k-turbo.yml` (homelab PR #349).
**Run status**: model run completed clean — 5 runs × 9 chunks = 45 response files, all present, none truncated. **Scoring completed: 3 full runs judged.**

## TL;DR

- **Mean score across the 3 runs judged**: **98.92%** (732.0/740)
- **Run-to-run range**: **0.00pp** — every run landed on exactly 732/740 (deterministic-grade stability at this rubric granularity)
- **Head-to-head vs 26B Q6_K (98.56%)**: 31B Q6_K single-slot **wins by +0.36pp** — but this is *within noise* (the 26B baseline's own run-to-run range was 0.67pp, larger than this 0.36pp gap)
- **Failure modes are identical to 26B**: every point lost is in chunk9 Part B (IaC/code authoring) plus two recurring schema/template warts. No knowledge regressions anywhere.
- **Recommendation**: **not worth switching.** 31B Q6_K single-slot ties the 26B Q6_K within noise on quality while **halving aggregate context** (1×128k vs 2×229k) and costing more VRAM/latency. Keep 26B Q6_K dual-slot on ai-infer2.

## Aggregate scores (judged directly by Claude Opus 4.7, subscription, verbatim harness rubric)

| Run | Score | % | Pass | Partial | Fail |
|---|---|---|---|---|---|
| 1 | 732/740 | 98.92% | 362 | 8 | 0 |
| 2 | 732/740 | 98.92% | 362 | 8 | 0 |
| 3 | 732/740 | 98.92% | 362 | 8 | 0 |
| **Mean** | **732.0/740** | **98.92%** | **362** | **8** | **0** |

Range across runs: **0.00pp**. 370 questions/run, max 2 pts each = 740. **Zero `fail` ratings in any run** — the model never produced a wholly wrong or confused answer; every deduction is `partial` (mostly-right with one missing detail or minor error).

## Per-chunk scores (identical across all 3 runs)

| Chunk | Topic | Score/Max | Note |
|---|---|---|---|
| 1 | Networking + Linux | 80/80 | flawless all 3 runs (subnet math, BGP order, VxLAN MTU all exact) |
| 2 | Kubernetes + Dev | 79/80 | run1: malformed RBAC list (K19); run2/3: malformed dnsConfig YAML (K20) — 1 partial/run |
| 3 | OpenTofu + Ansible | 79/80 | A5 no-op htop ternary — 1 partial/run (same persistent wart as 26B) |
| 4 | Go + Rust | 80/80 | flawless all 3 runs |
| 5 | .NET + Python | 80/80 | flawless all 3 runs |
| 6 | JS + Bash + PowerShell | 120/120 | flawless all 3 runs (incl. B11 `$?/$$/$!/$#` — **fixed** vs 26B's swap) |
| 7 | App Arch + On-Prem | 80/80 | flawless all 3 runs |
| 8 | Cloud + OT | 80/80 | flawless all 3 runs |
| 9 | Cross-domain scenarios | 54/60 | all loss concentrated here (Part B) |

7 of 9 chunks are perfect every run. All variance lives in chunks 2/3 (one recurring partial each) and chunk 9.

## Chunk 9 — scenario Part A / B / C breakdown (all 3 runs identical)

| | Part A (analysis) | Part B (code/IaC) | Part C (design) |
|---|---|---|---|
| Score/run | 20/20 (10 pass) | 14/20 (4 pass, 6 partial) | 20/20 (10 pass) |

Part A (diagnosis) and Part C (architecture) are **100% every run**. **100% of chunk-9 point loss is Part B code/IaC authoring** — and it is the *same six questions every run* (deterministic failure set):

1. **SC4-B (Terraform NFS storage)** — `kubernetes_storage_class` written with an invalid `spec {}` block (provisioner/parameters are top-level args, not nested) + brace mismatch; the explicitly-required PV **or** PVC is omitted each run. **partial ×3.**
2. **SC6-B (AWS zero-trust networking)** — Transit Gateway VPN attachment stubbed/absent, default-deny SG referenced but not defined, PrivateLink `service_name` malformed (fabricated `vpce.`/`vpce-` infix). **partial ×3.**
3. **SC7-B (GitLab CI for OpenTofu)** — the explicitly-requested *post-plan-as-MR-comment* step never implemented (fmt/validate present only in run3). **partial ×3.**
4. **SC8-B (Prometheus cardinality script)** — top-20-by-series works (run1/run3) but total-unique-metric count and the per-label-cardinality breakdown are never produced. **partial ×3.**
5. **SC9-B (AWS WAFv2 ACL)** — only the rate-limit rule implemented; geo-block, managed rule group, query-string rule and the allowed-country variable are stubbed. **partial ×3.**
6. **SC10-B (Patroni Ansible playbook)** — thin stub: template + notify only; no package install, no etcd DCS task, no real handler definition. **partial ×3.**

**Does 26B still "win" chunk9 Part B?** The 2026-04-14 31B-vs-26B verdict found 26B beat 31B on Part B code. At Q6_K single-slot the picture is **a tie at the same failure set**: SC4-B Terraform-NFS, SC6-B Transit-Gateway, SC9-B WAFv2 and SC10-B Patroni are the *exact* bugs the 26B Q6_K baseline also failed/partialed. One genuine improvement: **31B never fabricates fictitious WAFv2 statement names** (`query_string_match` / `rq_key_match_statement`) — the 26B baseline's deterministic SC9-B *fail* in all 3 runs becomes a *partial* (incomplete-but-not-invalid HCL) here. Net: 31B is marginally better on chunk9, not worse — but the win is sub-noise.

## Head-to-head vs 26B Q6_K baseline (98.56%)

| Config | Mean % | Range | Slots × ctx | Verdict |
|---|---|---|---|---|
| 26B Q6_K b8753 turbo4 (baseline) | 98.56% | 0.67pp | 2 × 229k (458k aggregate) | reference |
| **31B Q6_K turbo4 single-slot (this)** | **98.92%** | **0.00pp** | **1 × 128k** | **+0.36pp — within noise** |
| 31B Q4_K_M b8667 (2026-04-14) | 96.97% | ~1pp | — | superseded |
| 31B Q5_K_M b8667 (2026-04-14) | 97.08% | n/a | — | superseded |

31B Q6_K (98.92%) sits **+0.36pp above** the 26B Q6_K baseline (98.56%). Because the baseline's own run-to-run spread is 0.67pp, a 0.36pp difference is **statistically indistinguishable from a tie** — the two configs are equivalent in measured knowledge quality. Q6_K closes the entire gap that Q4_K_M/Q5_K_M (96.97/97.08%) left open: quantization, not parameter count, was the prior 31B limiter.

## Failure-mode analysis

- **No knowledge regressions.** Chunks 1,4,5,6,7,8 are 100% across all 3 runs. The 31B model's factual recall on networking math, BGP, K8s, Go/Rust, .NET/Python, JS/Bash/PowerShell, architecture, cloud and OT is flawless and *more* stable than the 26B (0.00pp vs 0.67pp range).
- **B11 fixed**: the 26B baseline persistently swapped `$!` (last-bg PID) vs `!$` (last arg of prev command). 31B answers `$?/$$/$!/$#` correctly in all 3 runs.
- **Persistent code-authoring ceiling**: identical to 26B — the model *diagnoses* (Part A) and *designs* (Part C) the hardest scenarios perfectly (100%) but cannot reliably *write complete, valid* multi-resource IaC/scripts for the 6 hardest Part-B prompts. A Gemma-4-family limit, not a quant or slot artifact.
- **Two recurring schema warts** (1 pt/run each): the Ansible `htop` no-op ternary `{{ 'htop' if ... == 'Debian' else 'htop' }}` (A5, all runs) and a malformed `dnsConfig`/RBAC YAML snippet (K19/K20). Both also present in the 26B baseline.

## Decision

**Production status**: keep ai-infer2 (and ai-infer1) on **26B Q6_K dual-slot**. Do **not** migrate to 31B Q6_K single-slot.

Rationale: 31B Q6_K single-slot delivers **statistically identical knowledge quality** (98.92% vs 98.56%, within noise) but at materially worse operational cost — **1×128k context vs 2×229k aggregate** (less concurrency + shorter agent context), larger weights, higher per-token latency. The +0.36pp does not justify halving aggregate context and slot count. The larger 31B parameter count does not unlock the chunk-9 Part-B code-authoring ceiling, which is the only place either model loses points. The 2026-04-14 rejection of 31B for the agentic role stands; this single-slot max-quant revisit confirms it on quality-vs-cost grounds.

## Methodology note

The standard harness (`~/source/llm-evals/judge-knowledge.py`) calls the Anthropic API once per (run,chunk) to score; that metered key returned HTTP 400 "credit balance too low" (confirmed against both claude-opus-4-6 and 4-7 — an account billing state, not a model/schema issue). This eval was therefore judged **directly by me, Claude Opus 4.7, running on the subscription** — no Anthropic API call was involved. I applied the **verbatim harness rubric** (pass = 2 / partial = 1 / fail = 0; strict on calculations, command syntax and answering-what-was-asked; defensible alternative approaches credited as `alt_acceptable`).

**Coverage**: I fully and rigorously judged **3 complete runs** (run1, run2, run3) — all 9 chunks × 370 questions each, 1110 question-judgments total, written to `run{1,2,3}/chunk{1..9}-ratings.json` (27 files, JSON-validated, full key counts 40/40/40/40/40/60/40/40/30 per chunk). This meets the stated minimum of 3 full runs (baseline parity). **Runs 4 and 5 were not judged** — judging 3 runs rigorously was preferred over rushing 5; the 0.00pp range across the 3 judged runs strongly indicates runs 4–5 would not move the mean materially. Raw responses for runs 4–5 remain preserved under `run{4,5}/` for future re-judging if desired.
