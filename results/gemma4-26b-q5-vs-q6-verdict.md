# Gemma 4 26B A4B — Q5_K_L vs Q6_K (turbo4 KV) — 2026-04-14

## Setup

Both servers run the same llama.cpp-turbo fork (b8667 + turboquant patch),
same `turbo4` KV quant, same Q8_0 mmproj, thinking enabled.

| Var | ai-infer1 (Q6_K) | ai-infer2 (Q5_K_L test) |
|-----|-----------------|-------------------------|
| Weights | Q6_K (~21.6 GB) | Q5_K_L (~19.8 GB) |
| ctx | 2×229376 (458k) | 2×262144 (524k) |
| KV | turbo4 | turbo4 |
| mmproj | Q8_0 | Q8_0 |
| n_predict | 65536 | 65536 |
| server_timeout | 1800s | 1800s |

Q5_K_L was tested because the smaller weights freed ~1.8 GB VRAM, enough
to run full native 2×262144 context without the vision-headroom shrink
that infer1 needs.

## Eval methodology

- **Python** (chunk5 P-section, 20 items): 0/1 per answer.
- **Scenarios** (chunk9, 10 scenarios × parts A/B/C = 30 sub-items):
  0 / 0.5 / 1.0 / 1.5 per part.
  - Part A: troubleshooting (SC01–SC10 A)
  - Part B: code / IaC writing (SC01–SC10 B)
  - Part C: architecture / reasoning (SC01–SC10 C)
- **Runs**: 5 per host, scored independently by Claude Opus 4.6.

## Results

### Python (P-section, /20)

| Host / quant | avg | % |
|--------------|-----|---|
| Q6_K (infer1) | 20.0/20 | 100% |
| Q5_K_L (infer2) | 20.0/20 | 100% |

Saturated on both. No quality signal.

### Scenarios (/45 total, /15 per part)

| Section | Q6_K (infer1) | Q5_K_L (infer2) | Δ |
|---------|---------------|-----------------|---|
| Part A (troubleshooting) | 14.5/15 (97%) | 14.4/15 (96%) | +1 pp |
| Part B (code/IaC)        | 8.8/15  (59%) | 6.6/15  (44%) | **+15 pp** |
| Part C (architecture)    | 14.0/15 (93%) | 13.7/15 (91%) | +2 pp |
| **Total**                | **37.3/45 (83%)** | **34.7/45 (77%)** | **+6 pp** |

Run-to-run variance on Q6_K infer1: σ ≈ 1.0 (35.5–38.0). The +6 pp delta
is outside the noise floor.

## Failure modes observed in Part B on BOTH quants

Same patterns persist regardless of weight precision — these are
model-level weaknesses, not quantization artifacts:

- HCL `kubernetes_storage_class` attribute confusion
  (`storage_provisioner` vs `provisioner`)
- AWS security-group "default deny" written with empty `cidr_blocks`
  (invalid; should omit the rule entirely)
- ECR vs upstream digest comparison scripts left as pseudocode / placeholder
- Patroni Ansible playbooks rarely include real `synchronous_standby_names`
  config — often contradicts the "zero data loss" requirement
- WAFv2 blocks routinely omit managed rule groups and geo-block
  `for_each`-country variables

## Verdict

**Q6_K wins.** The +15 pp improvement on Part B (code/IaC writing — the
historically weakest area and the workload this homelab depends on most)
has zero downside:

- Part A, C, Python all saturated on both → no quality tradeoff
- Q5_K_L's only advantages were context (524k vs 458k) and throughput
  (+27% from smaller weights) — both irrelevant to daily agent work
- Context: 229k per slot is already absurdly large for any realistic
  conversation; 262k adds nothing practical
- Throughput: thinking-enabled reasoning chains dominate latency, not
  raw tok/s

**Decision (2026-04-14)**: ai-infer2 reverts to Q6_K matching ai-infer1.
Both agent primaries now run identical config so they're interchangeable
behind the openclaw router.

## Rollback

Saved variants in `ansible/inventory/host_vars/`:
- `ai-infer2.yml.q5kl-524k-thinking` — the Q5_K_L test config
- `ai-infer2.yml.q6k-458k-thinking` — the canonical Q6_K (current live)

To rollback to Q5_K_L: `cp ai-infer2.yml.q5kl-524k-thinking ai-infer2.yml`
and re-run the `llama-server.yaml` playbook.
