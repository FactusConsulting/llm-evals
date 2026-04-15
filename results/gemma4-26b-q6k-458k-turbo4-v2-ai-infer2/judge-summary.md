# Judge Summary — gemma4-26b-q6k-458k-turbo4-v2-ai-infer2

Stable two-judge scoring with default-to-pass rubric. Each run scored independently by Judge A and Judge B (both Claude Opus 4.6, separate agent processes), with disagreements resolved via mean(A,B) per question.

## Per-run results

| Run | Score | % | Pass | Partial | Fail | alt_acceptable | Inter-judge agreement |
|---|---|---|---|---|---|---|---|
| 1 | 726/740 | 98.11% | 357 | 12 | 1 | 49 (13.2%) | 97.0% |
| 2 | 731/740 | 98.78% | 362 | 7 | 1 | 49 (13.2%) | 97.8% |
| 3 | 731/740 | 98.78% | 361 | 9 | 0 | 64 (17.3%) | 96.8% |
| **Mean** | **729.3/740** | **98.56%** | 360 | 9.3 | 0.7 | 54 (14.6%) | 97.2% |

Range across runs: **0.67pp** — sub-noise-floor variance.

## Per-judge raw scores

| Run | Judge A | Judge B | Mean(A,B) |
|---|---|---|---|
| 1 | 97.16% | 97.57% | 97.36% |
| 2 | 98.24% | 98.24% | 98.24% |
| 3 | 98.24% | 97.70% | 97.97% |

(Final scores in the table above are slightly higher than mean(A,B) because per-question disagreements get resolved via rounded-mean which favors the higher rating when borderline.)

## Variance comparison vs older methodology

| Method | Run 1 | Run 2 | Run 3 | Mean | Range |
|---|---|---|---|---|---|
| Single ad-hoc Opus judge (old method) | 97.30% | 98.65% | 96.22% | 97.39% | **2.43pp** |
| `/judge` skill v1 (strict-to-reference) | 91.01% | 91.22% | 90.74% | 90.99% | 0.48pp |
| **`/judge` skill v2 (default-to-pass)** | **98.11%** | **98.78%** | **98.78%** | **98.56%** | **0.67pp** ⭐ |

The v2 methodology gives **3.6× lower run-to-run variance** than ad-hoc judging while preserving accuracy (matches the ad-hoc baseline of ~97.4% within noise).

## Persistent failure modes (concrete bugs caught by judges)

These are the same questions the model fails consistently across all 3 runs — they represent real model limitations, not judging artifacts:

1. **SC9-B** (AWS WAFv2) — model invents fictitious statement names like `query_string_match` / `rq_key_match_statement`. Real WAFv2 syntax requires `byte_match_statement { field_to_match { query_string {} } }`. Both judges + deterministic HCL validator agree this is wrong in all 3 runs.
2. **SC4-B** (Terraform NFS) — model uses `kubernetes_csi_volume` (not a real Terraform resource — should be `kubernetes_persistent_volume_v1` with `csi { driver = "nfs.csi.k8s.io" }`). Flaky: fails in run 1 + 3, passes in run 2.
3. **SC6-B** (AWS Transit Gateway) — model writes incomplete HCL with hardcoded `for_each` set instead of variable list, missing VPN attachment, missing default-deny SG. Partial in all runs.
4. **SC10-B** (Patroni Ansible playbook) — model writes a template + service stub but skips package install, etcd DCS config, full Patroni handlers. Partial in all runs.
5. **A5** (Ansible single-task htop install) — model emits `'htop' if ansible_os_family == 'Debian' else 'htop'` which is a no-op ternary; the RedHat branch installs only epel-release without htop. Partial in all runs.
6. **B11** (`$!` vs `!$` in bash) — model swaps the two: `$!` is "PID of last background", `!$` is "last argument of previous command". Partial in runs where it appears.

## Things the judges credited as `alternative_acceptable`

The model frequently solved problems differently than the reference, and judges correctly credited these as valid:

- N5 cert mismatch causes — model lists IP-vs-hostname access and self-signed-without-SAN as causes (different than reference's SNI mismatch + wrong-server but equally valid)
- Many "explain X" questions — model uses different but equivalent technical explanations
- Some "show example" questions — model picks different valid examples than the reference
- Code/jq questions where model's syntax works correctly but uses a different pattern than reference

This is the methodology working as intended: the model's solution is judged on whether it solves the problem, not whether it matches the reference word-for-word.

## Files in this directory

- `run{1,2,3}/chunk{1..9}-response.txt` — raw model output
- `run{1,2,3}/judge.json` — full per-question judging result with both judges' calls + decided rating
- `judge-summary.md` — this file
- `verdict.md` — model-level verdict (cross-run analysis + production recommendation)
- `chunks/` → symlink to `../gemma4-26b-q6k/chunks/` (shared question files)
- `run-chunk.sh` — wrapper script to run new chunks against this server
