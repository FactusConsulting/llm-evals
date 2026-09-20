# Judge summary — GLM-5.3-Flash UD-Q2_K_XL on gx10

Judged 2026-09-20 with `judge-llm-eval/2.0`: two independent Opus 5 judges per run,
per-question mean(A,B), 370 questions per run.

## Aggregate

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 731/740 | 98.78% | 362 | 7 | 1 | 99 (26.8%) |
| 2 | 732/740 | 98.92% | 362 | 8 | 0 | 120 (32.4%) |
| 3 | 730/740 | 98.65% | 361 | 8 | 1 | 98 (26.5%) |
| **Mean** | **731.0/740** | **98.78%** | **361.7** | **7.7** | **0.7** | **105.7 (28.6%)** |

Range across runs: **0.27 pp** — below the 0.4-0.9 pp band the procedure calls healthy.

## Inter-judge agreement

| Run | Judge A % | Judge B % | Agreement |
|---|---|---|---|
| 1 | 98.38% | 98.51% | 98.65% (365/370) |
| 2 | 98.51% | 98.65% | 98.65% (365/370) |
| 3 | 97.97% | 98.24% | 97.84% (362/370) |

Per-judge variance from the run mean is 0.14-0.68 pp. `alternative_acceptable` sits at the
top of the 10-30% target band, so the judges were not reading the reference as a checklist.

## Per-chunk (%)

| Chunk | Topic | run1 | run2 | run3 | Mean |
|---|---|---|---|---|---|
| 1 | Networking + Linux | 100.0 | 100.0 | 100.0 | **100.00** |
| 2 | Kubernetes + Dev | 100.0 | 98.8 | 98.8 | 99.17 |
| 3 | OpenTofu + Ansible | 98.8 | 100.0 | 98.8 | 99.17 |
| 4 | Go + Rust | 100.0 | 100.0 | 100.0 | **100.00** |
| 5 | .NET + Python | 98.8 | 98.8 | 100.0 | 99.17 |
| 6 | JS + Bash + PowerShell | 98.3 | 99.2 | 100.0 | 99.17 |
| 7 | App arch + on-prem | 100.0 | 100.0 | 100.0 | **100.00** |
| 8 | Cloud + OT | 100.0 | 98.8 | 98.8 | 99.17 |
| 9 | Scenarios | 91.7 | 93.3 | 88.3 | **91.11** |

## Chunk 9 by part

| Part | What it asks | run1 | run2 | run3 | Mean |
|---|---|---|---|---|---|
| A | Analysis | 100.0 | 100.0 | 100.0 | **100.0** |
| B | Working code / IaC | 75.0 | 80.0 | 65.0 | **73.3** |
| C | Architecture / trade-offs | 100.0 | 100.0 | 100.0 | **100.0** |

The entire deficit is Part B. Analysis and architecture are perfect in every run.

## Persistent failure modes

Downgraded in all three runs:

| Question | Mode |
|---|---|
| SC4-B | HCL does not parse — several arguments on one line, comma-separated |
| SC9-B | Same HCL compression, plus `AWSManagedRulesCommonRuleSet` misspelled and `field_to_match { type = ... }` instead of the nested `query_string {}` |

Downgraded in two of three runs: DN20 (`AddFilter` for `AddEndpointFilter`), PS18
(`ICustomRule` for `IScriptRule`), OT19 (ATT&CK-for-ICS technique IDs misattributed),
SC5-B (comma-separated Go import block), SC6-B, SC10-B.

One dominant mode, seen by all six judges independently: the model compresses
multi-line syntax onto one line with comma or semicolon separators. HCL2 allows at
most one argument in a single-line block and no commas; Go import blocks are
newline-separated. The semantics, resource schemas and logic are correct underneath —
only the separators are invalid.

The second mode is exact identifiers: method names, CLI flag names, subresource names
(`pods/logs` for `pods/log`), ATT&CK IDs. Prose describing the same thing is right.

## Deterministic Part B validation

`validators/validate-part-b.py` on each run's chunk9:

| Run | Valid | Invalid | Unvalidated | Blocks |
|---|---|---|---|---|
| 1 | 6 | 4 | 2 | 12 |
| 2 | 6 | 4 | 2 | 12 |
| 3 | 7 | 4 | 2 | 13 |

The validator and the judges agree on the HCL failures; two judges re-ran `tofu fmt`
themselves and got the same rejection. The YAML failures it reports on SC10 (and SC7 in
run2) are false positives: the block is a `patroni.yml.j2` Jinja template, so raw `{{ }}`
is correct there and is not valid YAML by design. SC5's `sql` and `go` blocks are
"unvalidated" (no parser wired up), not failures.

## Answer-key gap found

`skills/judge-llm-eval/answers/chunk7-8-architect.md` covers only Q1-12 of each of the
four sections. AA13-20, OP13-20, CL13-20 and OT13-20 — 32 questions — have no reference,
and were scored from judge knowledge per judge.md. Worth filling in before the next
campaign.
