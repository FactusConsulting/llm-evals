# Judge summary — GLM-5.3-Flash UD-Q4_K_XL across both GB10 boxes (RPC)

Judged 2026-10-24 with `judge-llm-eval/2.0`: two independent Opus judges (Claude Code
subagents), per-question mean(A,B), 370 questions. One run — the routine for a quant
change of a model that already has a three-run baseline
(`glm5.3-flash-q2kxl-mtp-2x128k-gx10`, 98.69 %, range 0.13 pp).

## Aggregate

| Run | Score | % | Pass | Partial | Fail | alt_acceptable |
|---|---|---|---|---|---|---|
| 1 | 728/740 | **98.38 %** | 358 | 12 | 0 | 56 (15.1 %) |

## Inter-judge agreement

| Judge A % | Judge B % | Agreement |
|---|---|---|
| 98.38 % (728/740) | 97.97 % (725/740) | 99.19 % (367/370) |

Three disagreements, all pass-vs-partial, all resolved to pass by mean(A,B): A20 (the
non-existent `community.aws.elb_application_lb_target` module — B docked it, A let it
pass on the surrounding design), SC5-B and SC8-B (code B judged would not run as written).
Per-judge variance from the mean is 0.0–0.41 pp.

## Per-chunk (%)

| Chunk | Topic | run1 | Q2 three-run mean |
|---|---|---|---|
| 1 | Networking + Linux | 100.0 | 100.00 |
| 2 | Kubernetes + Dev | 100.0 | 99.17 |
| 3 | OpenTofu + Ansible | 97.5 | 99.17 |
| 4 | Go + Rust | 100.0 | 100.00 |
| 5 | .NET + Python | 100.0 | 99.17 |
| 6 | JS + Bash + PowerShell | 96.7 | 99.17 |
| 7 | App arch + on-prem | 100.0 | 99.58 |
| 8 | Cloud + OT | 98.8 | 98.75 |
| 9 | Scenarios | 91.7 | 91.11 |

## Chunk 9 by part

| Part | What it asks | run1 | Q2 mean |
|---|---|---|---|
| A | Analysis | 100.0 | 100.0 |
| B | Working code / IaC | 75.0 | 73.3 |
| C | Architecture / trade-offs | 100.0 | 100.0 |

The deficit is Part B, as on Q2. Analysis and architecture are perfect.

## Failure modes

All twelve partials, grouped:

| Mode | Questions |
|---|---|
| Multi-line syntax compressed onto one line with comma/semicolon separators (HCL single-line blocks with several arguments; multi-line blocks opened with an argument on the brace line) | SC4-B, SC9-B |
| Code that does not parse or run for another reason | SC6-B (security groups reference each other inline → dependency cycle; `var.customer_gateway_id` undeclared), SC7-B (`curl --form-urlencode` is not a flag; `when: manual` beside `rules:`; plan artifact path mismatch), SC10-B (`- name etcd DCS`, colon missing) |
| Shell/Jinja mechanics wrong under default settings | A19 (`{% endif %}` at end of line + `trim_blocks` comments out the rest of the nginx upstream block), B8 (EXIT trap set before `mkdir` breaks the lock's mutual exclusion), B19 (xargs exit 123 treated as success) |
| Confident false claims about a runtime | PS14 (cmdlets "cannot" be called from class methods), PS19 (PowerShell 7 "does not" use CLIXML), CL11 (EBS 0.1–0.2 % AFR quoted as "99.8–99.9 %") |
| Self-contradiction | A17 (`run_once` example contradicts its stated goal; the model notices mid-answer) |

The two modes that defined the Q2 verdict — one-line HCL compression and wrong exact
identifiers — are both present at Q4 (SC4-B/SC9-B; A20, OT19's T0842-for-T0841 let
through as a slip). The quant did not create them and does not remove them.

## Deterministic Part B validation

`validators/validate-part-b.py` on run1 chunk 9: 11 blocks, **6 valid, 3 invalid,
2 unvalidated** (SC5's `sql`/`go`, no parser). Scenarios with an invalid block: SC4, SC9,
SC10. All three were already rated partial by both judges, so the hard signal changed
nothing. Unlike the Q2 run, the SC10 YAML rejection is genuine — a missing colon, not a
Jinja template read as YAML.

## Comparison with the Q2 baseline

| | UD-Q2_K_XL, one box, 2×131k, q4_0 KV | UD-Q4_K_XL, two boxes over RPC, 1×262k, q8_0 KV |
|---|---|---|
| Knowledge | 98.69 % mean of 3 (98.65 / 98.78 / 98.65) | 98.38 % (one run) |
| Part B | 73.3 % mean | 75.0 % |
| Agreement | 97.8–98.7 % | 99.2 % |
| alt_acceptable | 27–33 % | 15.1 % |

−0.31 pp against the Q2 mean, inside the < 1 pp noise band the method defines for
single runs. Judged by different judge instances with a lower `alternative_acceptable`
rate (15 % vs ~30 %), i.e. this pair read the key slightly more literally, which moves
the score down, not up. The suite is saturated at this level (README): it cannot rank
Q4 against Q2, only confirm that nothing broke.
