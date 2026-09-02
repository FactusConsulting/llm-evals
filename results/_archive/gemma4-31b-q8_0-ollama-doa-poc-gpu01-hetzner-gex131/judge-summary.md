# Judge summary — gemma4-31b-q8_0 (ollama, doa-poc-gpu01, Hetzner GEX131)

**Model**: `gemma4:31b-q8_0` (from `unsloth/gemma-4-31B-it-GGUF` — `gemma-4-31B-it-Q8_0.gguf`, 30.4 GiB)
**Host**: doa-poc-gpu01 / 23.88.29.100 (Hetzner GEX131, 1× RTX PRO 6000 Blackwell Max-Q, 96 GB VRAM)
**Runtime**: Ollama 0.21.0, NVIDIA driver 580.126.09-open, CUDA 13.0, kernel 6.8.0-110-generic
**Endpoint**: `http://23.88.29.100:11434/v1/chat/completions` (OpenAI-compatible)
**Inference**: `max_tokens=49152`, `temperature=0.1`, `top_p=0.95`, thinking ENABLED (Gemma 4 default)
**Judging methodology**: `judge-llm-eval/2.0` — two parallel Opus 4.7 judges per run with mean(A,B) aggregation
**Generation wall time**: ~54 min (27 chunks × ~120 s mean)
**Loop-detection wall time**: ~37 min (12 scenarios)

## Aggregate scores

| Run | Score | % | Pass | Partial | Fail | alt_acceptable | inter-judge agreement |
|---|---|---|---|---|---|---|---|
| 1 | 730/740 | **98.65%** | 360 | 10 | 0 | 85 (23.0%) | 99.2% |
| 2 | 737/740 | **99.59%** | 367 | 3 | 0 | 63 (17.0%) | 99.2% |
| 3 | 736/740 | **99.46%** | 366 | 4 | 0 | 28 (7.6%) | 98.6% |
| **Mean** | **734.3/740** | **99.23%** | **364.3** | **5.7** | **0.0** | **58.7 (15.9%)** | **99.0%** |

**Range across runs**: 0.94pp — slightly above the "healthy" 0.4–0.9pp band, driven by run 1 being ~1pp below runs 2/3. Not problematic but above noise floor — could be real sampling jitter at temp 0.1 or minor judge variance on chunk 3 between runs (run 1 chunk 3 = 96.25 %, runs 2/3 = 100%).

Run 3's alt_acceptable rate (7.6%) is below the 10-30% target. Judge B's run-3 report notes this was because "most answers happened to align with the reference's approach and items" — not a sign of strict judging (inter-judge agreement is 98.6% and per-judge pct is the same as run 2). Acceptable.

## Per-judge breakdown

| Run | Judge A % | Judge B % | Δ |
|---|---|---|---|
| 1 | 98.51% (359p/11pa/0f, alt 15.1%) | 98.38% (358p/12pa/0f, alt 12.7%) | 0.13pp |
| 2 | 99.32% (365p/5pa/0f, alt 8.6%) | 99.46% (366p/4pa/0f, alt 14.3%) | 0.14pp |
| 3 | 99.05% (362p/7pa/1f, alt 5.4%) | 99.19% (367p/3pa/0f, alt 5.1%) | 0.14pp |

Per-run judge delta ≤ 0.14pp — well inside the ±0.5 pp stability target.

## Per-chunk scores (mean across 3 runs)

| Chunk | Topic | Run 1 | Run 2 | Run 3 | Mean |
|---|---|---|---|---|---|
| 1 | Networking + Linux | 100% | 100% | 100% | **100.00%** |
| 2 | Kubernetes + Dev | 100% | 100% | 100% | **100.00%** |
| 3 | OpenTofu + Ansible | 96.25% | 100% | 100% | 98.75% |
| 4 | Go + Rust | 98.75% | 100% | 98.75% | 99.17% |
| 5 | .NET + Python | 100% | 100% | 100% | **100.00%** |
| 6 | JS + Bash + PowerShell | 99.17% | 100% | 99.17% | 99.45% |
| 7 | App Architecture | 100% | 100% | 100% | **100.00%** |
| 8 | OnPrem + Cloud + OT | 100% | 100% | 100% | **100.00%** |
| 9 | Cross-domain scenarios | 91.67% | 95.0% | 96.67% | 94.45% |

**5/9 chunks perfect across all 3 runs.** Chunk 9 (scenarios) is the only material weakness — see Part B breakdown below.

## Chunk 9 Part A / B / C breakdown (mean across 3 runs)

| Part | Focus | Run 1 | Run 2 | Run 3 | Mean |
|---|---|---|---|---|---|
| A | Analysis / diagnosis | 100% | 100% | 100% | **100.00%** |
| B | Code / IaC writing | 75.0% | 85.0% | 90.0% | 83.33% |
| C | Design / recommendation | 100% | 100% | 100% | **100.00%** |

Part B improved monotonically run-to-run — 75→85→90% — likely because the partials judges flagged are borderline (skeletal playbooks, for_each placeholder issues) and temp-0.1 sampling happened to produce slightly more complete code in later runs.

## Persistent Part B failure modes (flagged in ≥2 runs by both judges)

1. **SC6-B (AWS PrivateLink HCL)** — `for_each` hardcodes `service_name = ...execute-api` instead of interpolating `each.value` for s3/rds/ecr. Flagged partial in runs 1+2, passed run 3.
2. **SC10-B (Patroni Ansible playbook)** — skeletal: omits package install, etcd DCS install/config, full `patroni.yml` template body. Flagged partial in all 3 runs by at least one judge.
3. **SC7-B (GitLab CI pipeline)** — missing MR comment posting + environment/backend config. Flagged partial in run 1+2.
4. **SC8-B (Prometheus cardinality)** — jq/PromQL shape is right but omits per-label analysis for the top cardinality metric. Flagged partial in runs 1+2.
5. **SC9-B (AWS WAFv2)** — invalid field shorthand and omits geo-block + managed rule groups. Flagged partial in run 1 by Judge B only.

These match the persistent failure-spots documented for the 26B Q6_K baseline — identical weaknesses, plus marginally better execution on 4/5 items at Q8_0.

## Notable chunk-level downgrades (single-run)

- **G9 (Go MVS)**: Judge A run 3 flagged as fail ("lowest version satisfying constraints" vs the correct "maximum of the minimums"). Judge B scored it pass. Aggregated to `partial` via mean(A,B). Other runs: pass. This is on the rubric's "default to pass" edge.
- **N8 (BGP path selection)**: Judge B run 2 flagged incorrect "Locally Originated = Next hop 0.0.0.0" definition — one of very few factual errors caught in 1110 question-ratings total.
- **PS12 (PowerShell interpolation)**: Judge B run 3 flagged invalid `$($Get-Date)` subexpression syntax (the extra `$` is a model error).

## Validator (chunk 9 Part B)

`python3 skills/judge-llm-eval/validators/validate-part-b.py` was run on all 3 chunk-9 responses. `pyyaml` is not installed on the eval host (PEP 668 blocks pip), so YAML blocks register as invalid-due-to-missing-dep rather than genuine syntax errors — the 2–3 "invalid" flagged YAML blocks per run are validator environment issues, not model output issues. Judges evaluated chunk 9 Part B directly and identified the real weaknesses listed above.

## Cost

- Generation: ~54 min ollama time on 1× RTX PRO 6000 Blackwell Max-Q (no measurable $ cost — on-prem GPU)
- Judging: 6 parallel Opus 4.7 sub-agents × ~330-380k tokens each ≈ 2.2M tokens total
