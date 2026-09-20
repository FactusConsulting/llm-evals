# Judge summary — GLM-5.3-Flash UD-Q2_K_XL on gx10

Judged 2026-09-20 with `judge-llm-eval/2.0`: two independent Opus 5 judges per run,
per-question mean(A,B), 370 questions per run.

Scored in two rounds. Round 1 found that `answers/chunk7-8-architect.md` covered only
Q1-12 of each of its four sections, so AA13-20, OP13-20, CL13-20 and OT13-20 — 32 of the
80 questions in chunks 7 and 8 — had no reference and were scored from judge knowledge.
The key was then filled in and **chunks 7 and 8 were rescored from scratch by two fresh
judges per run**. Chunks 1-6 and 9 carry round 1's per-judge ratings. The numbers below
are the merged result; `run*/judge-round1.json` holds the pre-key scoring for comparison.

## Aggregate

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 730/740 | 98.65% | 361 | 8 | 1 | 100 (27.0%) |
| 2 | 731/740 | 98.78% | 361 | 9 | 0 | 123 (33.2%) |
| 3 | 730/740 | 98.65% | 361 | 8 | 1 | 109 (29.5%) |
| **Mean** | **730.3/740** | **98.69%** | **361** | **8.3** | **0.7** | **110.7 (29.9%)** |

Range across runs: **0.13 pp**.

## What the filled key changed

| | Round 1 | Round 2 |
|---|---|---|
| run1 | 98.78% | 98.65% |
| run2 | 98.92% | 98.78% |
| run3 | 98.65% | 98.65% |
| **Mean** | **98.78%** | **98.69%** |
| Range | 0.27 pp | **0.13 pp** |

Two final ratings moved across all 240 rescored questions, both from pass to partial:

- **run1 OT8** — the segmentation design is complete and correct, but the vendor example
  is fabricated: "Dell/Toff-in-T" is not a product, and Nozomi does not certify firewalls.
  OT8 always had a reference; round 1 simply missed this.
- **run2 AA19** — the question enumerates four dimensions (consistency, latency,
  complexity, offline support) and the answer never addresses latency. Not a factual
  error; a missed enumerated sub-part.

Everything else held. **Of the 32 questions that had no reference in round 1, exactly one
(AA19) changed its final rating.** The missing key was not inflating the score — the
chunk 7 and chunk 8 results stand.

The score moved -0.09 pp, well inside the noise floor, and the run-to-run range halved.
That is what a complete key buys: not a different answer, a more reproducible one.

## Inter-judge agreement

| Run | Judge A % | Judge B % | Agreement |
|---|---|---|---|
| 1 | 98.24% | 98.38% | 98.65% (365/370) |
| 2 | 98.24% | 98.38% | 98.11% (363/370) |
| 3 | 97.97% | 98.24% | 97.84% (362/370) |

Per-judge variance from the run mean is 0.27-0.68 pp. `alternative_acceptable` at 27-33%
sits at or just above the 10-30% target, so the judges were not reading the reference as
a checklist.

## Per-chunk (%)

| Chunk | Topic | run1 | run2 | run3 | Mean |
|---|---|---|---|---|---|
| 1 | Networking + Linux | 100.0 | 100.0 | 100.0 | **100.00** |
| 2 | Kubernetes + Dev | 100.0 | 98.8 | 98.8 | 99.17 |
| 3 | OpenTofu + Ansible | 98.8 | 100.0 | 98.8 | 99.17 |
| 4 | Go + Rust | 100.0 | 100.0 | 100.0 | **100.00** |
| 5 | .NET + Python | 98.8 | 98.8 | 100.0 | 99.17 |
| 6 | JS + Bash + PowerShell | 98.3 | 99.2 | 100.0 | 99.17 |
| 7 | App arch + on-prem | 100.0 | 98.8 | 100.0 | 99.58 |
| 8 | Cloud + OT | 98.8 | 98.8 | 98.8 | 98.75 |
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
| OT19 | ATT&CK-for-ICS technique IDs misattributed (see below) |

Downgraded in two of three runs: DN20 (`AddFilter` for `AddEndpointFilter`), PS18
(`ICustomRule` for `IScriptRule`), SC5-B (comma-separated Go import block), SC6-B, SC10-B.

One dominant mode, seen by all judges independently across both rounds: the model
compresses multi-line syntax onto one line with comma or semicolon separators. HCL2 allows
at most one argument in a single-line block and no commas; Go import blocks are
newline-separated. The semantics, resource schemas and logic are correct underneath —
only the separators are invalid.

The second mode is exact identifiers: method names, CLI flag names, subresource names
(`pods/logs` for `pods/log`), ATT&CK IDs. Prose describing the same thing is right.

### The ATT&CK IDs, verified

OT19 asks for tactics and example techniques from ATT&CK for ICS. The model names the
tactics and techniques correctly and then attaches wrong IDs. Verified against
attack.mitre.org while writing the key:

- `T0836` is Modify Parameter; Change Operating Mode is `T0858`
- `T0842` is Network Sniffing; Device Restart/Shutdown is `T0816`
- `T0846` is Remote System Discovery; `T0886` is Remote Services
- `T0856` is Spoof Reporting Message, not brute force

Three IDs the model used have also been restructured out of the current matrix:
`T0855` → `T1692` Unauthorized Message, `T0857` → `T1693.001`, `T0803` → `T1691` Block
Operational Technology Message. The key now records this so a judge does not penalise a
correct current ID as wrong, or credit a retired one.

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

## Answer key

`skills/judge-llm-eval/answers/chunk7-8-architect.md` now covers AA1-20, OP1-20, CL1-20
and OT1-20 — 80 answers, up from 48. The 32 new ones were written with exact identifiers
checked against primary sources (W3C Trace Context, B3, RFC 3580, attack.mitre.org, AWS
and Azure service docs, Gateway API, Ceph, ClusterLabs PAF, NAMUR NE 43). Where a number
could not be confirmed, the mechanism is named instead of a guess.
