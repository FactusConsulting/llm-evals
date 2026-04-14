# Gemma 4 31B vs 26B A4B — Eval verdict (2026-04-14)

**TL;DR**: **31B does not beat 26B on this workload.** Tested across two
quantizations (Q4_K_M, Q5_K_M) on ai-infer2 with full knowledge eval
suite (9 chunks). Both 31B configurations tie or lose to the 26B A4B
Q6_K production baseline within noise. The structural weaknesses that
show up in chunk 9 Part B (code/IaC writing) — broken AWS provider
DSL, incomplete Terraform scaffolding, thin Ansible playbooks — are
identical across Q4 and Q5, confirming it's a model-architecture /
training-data issue, not a quantization artifact.

**Hardware decision**: Do NOT invest in a 3rd RTX 5060 Ti (48 GB
total) or 2× RTX 5090 (64 GB total) to run 31B at Q6_K 2×260k ctx.
Precision was not the bottleneck.

## Test matrix

| Variant | Weights | KV | Context | Slots | Vision | Runs |
|---------|---------|-----|---------|-------|--------|------|
| 26B A4B Q6_K (baseline) | 21.6 GiB | turbo4 | 2×229k = 458k | 2 | Q8_0 mmproj | 4+ (prod) |
| 31B Q4_K_M | 18.24 GiB | turbo4 | 1×256k | 1 | off | 3 |
| 31B Q5_K_M | 21.04 GiB | turbo4 | 1×160k | 1 | off | 1 |

**Why two 31B variants?** The first test (Q4_K_M) was an unfair
comparison — 31B at lower precision vs 26B at higher precision. The
Q5_K_M re-test closes the precision gap to confirm whether it was
quantization suppressing 31B's potential, or something structural.

## Aggregate scores (knowledge eval, chunks 1-9, 385 max)

| Model | Run 1 | Run 2 | Run 3 | Avg | % |
|-------|-------|-------|-------|-----|---|
| 26B Q6_K (run4)   | —   | —   | —   | 371 / 385  | **96.36%** |
| 31B Q4_K_M        | 374 | 373 | 373 | 373.33 / 385 | **96.97%** |
| 31B Q5_K_M        | 373.75 | (not run) | (not run) | 373.75 / 385 | **97.08%** |

**Delta vs 26B Q6_K**:
- 31B Q4_K_M: +0.61 pp
- 31B Q5_K_M: +0.72 pp

Both deltas sit inside single-run variance (~1 pp observed run-to-run
noise on 26B). Neither is statistically distinguishable from a tie.

## Chunk 9 scenarios — the decisive chunk

Chunks 1-8 are saturated (~98-100%) across all three models — they are
factual Q&A where an experienced engineer would accept the answers
as correct. Chunk 9 is the only chunk where real differentiation
appears: 10 scenarios × 3 parts each, scored on partial credit.

| Part | Topic | 31B Q5_K_M | 31B Q4_K_M | 26B Q6_K |
|------|-------|------------|------------|----------|
| A | Troubleshooting / explanation | 14.25 / 15 (95%) | 14 / 15 (93%) | 14 / 15 (93%) |
| B | Code / IaC writing | 10.0 / 15 (67%) | 9.75 / 15 (65%) | **11.0 / 15 (73%)** |
| C | Architecture / reasoning | 14.0 / 15 (93%) | 15.0 / 15 (100%) | 13.5 / 15 (90%) |
| **Total** | | 38.25 / 45 | 38.75 / 45 | 38.5 / 45 |

**The 26B Q6_K actually WINS Part B** by 1 full point over both 31B
variants. Part B is the most operationally important sub-metric — it
tests whether the model can produce working Terraform, Ansible,
Python, jq, and AWS provider code. This is the daily agent workload.

## Recurring Part B failure modes (identical Q4 → Q5)

These are the specific errors that cost 31B Part B points in both
Q4_K_M and Q5_K_M runs, and which 26B Q6_K consistently avoids or
handles better:

1. **AWS provider DSL**: 31B writes `aws_wafv2_web_acl` with
   `rate_limit` block instead of `rate_based_statement`, and uses
   `field = "QUERY_STRING"` instead of the correct nested
   `field_to_match { query_string {} }`. 26B writes valid HCL.
2. **Terraform resource completeness**: 31B's Kubernetes storage
   answers include StorageClass + PVC but omit the PV resource.
   26B includes the full PV with NFS source block.
3. **Shell substitution**: 31B SC1-B produces broken `${{}% : *}`
   syntax in jq pipelines. 26B writes clean single-line jq.
4. **Ansible playbook scaffolding**: 31B produces template-only
   snippets without apt install, etcd DCS config, or handlers.
   26B's Patroni playbook is a working skeleton.
5. **WAF defense in depth**: 31B omits geo-block `for_each` country
   list and AWS managed rule group imports even when prompted.
   26B includes both.

These are **structural knowledge gaps** in the 31B model, not
quantization artifacts. Q4→Q5 closed the precision gap by adding
~3 GiB of weights, and the gaps persist identically.

## Why this is surprising (and what it means)

Conventional wisdom says a 31B dense model should outperform a 26B
MoE with 3.8B active params. On saturated factual Q&A (chunks 1-8)
both models top out. On the hard workload (Part B code writing),
the MoE architecture's specialization plus Google's training mix for
Gemma 4 26B A4B appears to cover the failure modes the 31B model has
in its training distribution.

**For agent workloads specifically**, the 26B A4B is the better pick:
- Faster tokens/sec (3.8B active params → ~3× throughput over 31B dense)
- Native vision (Q8_0 mmproj) for screenshot handling
- 2 slots × 229k ctx vs 1 slot × 160k ctx
- Slightly better Part B code output

## Hardware investment analysis (rejected)

To run 31B Q6_K 2×260k with turbo4 KV would require:

| Option | VRAM | Cost | Target fit? |
|--------|------|------|-------------|
| 3× RTX 5060 Ti 16GB | 48 GB | ~3k DKK (1 card) | ❌ 1 GB short |
| 4× RTX 5060 Ti 16GB | 64 GB | ~5-6k DKK (2 cards) + mobo/chassis/PSU | ✅ |
| 2× RTX 5090 32GB | 64 GB | ~20-25k DKK | ✅ + faster |

Measured KV-per-token on 31B dense with turbo4: **~42 bytes/token**
(from nvidia-smi on live ai-infer2 running 1×256k ctx). At 520k ctx
that's 21.8 GiB KV alone. Plus 25.5 GiB Q6_K weights + 2 GiB compute
= ~49 GiB total. Doesn't fit on current 2× 5060 Ti.

**None of these investments would change the verdict**, because the
failure modes are structural. Spending 5-25k DKK to reproduce a TIE
is bad ROI.

## Decision

**Keep 26B A4B Q6_K as production model on both ai-infer1 and
ai-infer2 (mirrored).** Revisit only if:
- Gemma 4.x / newer models become available
- A real agentic task suite (not knowledge Q&A) shows 31B winning
  meaningfully
- Q8_0 31B becomes evaluable on existing hardware via some trick
  (distributed RPC, tensor split across 3+ GPUs)

Variants saved in `ansible/inventory/host_vars/`:
- `ai-infer2.yml.q6k-26b-current` — production (restored)
- `ai-infer2.yml.q4km-256k-31b-test` — 31B Q4_K_M (rejected)
- `ai-infer2.yml.q5kl-524k-thinking` — 26B Q5_K_L (rejected earlier)

Eval data preserved in:
- `results/gemma4-31b-q4km-256k-turbo4-ai-infer2/` — 3 runs × 9 chunks
- `results/gemma4-31b-q5km-160k-turbo4-ai-infer2/` — 1 run × 9 chunks
- `loop-detection/results/gemma4-31b-q4km-256k-turbo4-run{1,2}/` — 1 full + 1 partial
