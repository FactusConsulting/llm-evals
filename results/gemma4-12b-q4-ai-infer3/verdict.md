# Verdict — Gemma 4 12B Q4_K turbo4 (ai-infer3)

**Knowledge/reasoning score: 92.4%** (684/740 points; 1 run, 1 Opus-subagent judge
per chunk, 370 scored items, 2026-06-09). Judged with the verbatim `judge-knowledge.py`
rubric (pass=2 / partial=1 / fail=0) via subscription-Opus subagents (the metered
ANTHROPIC key is dry).

## Per-chunk

| Chunk | Topic | Score |
| :-- | :-- | --: |
| 1 | networking / linux | 76/80 (95.0%) |
| 2 | k8s / dev | 76/80 (95.0%) |
| 3 | opentofu / ansible | 70/80 (87.5%) |
| 4 | go / rust | 76/80 (95.0%) |
| 5 | .net / python | 77/80 (96.3%) |
| 6 | js / bash / powershell | 111/120 (92.5%) |
| 7 | app-arch / on-prem | 77/80 (96.3%) |
| 8 | cloud / OT | 78/80 (97.5%) |
| 9 | **scenarios (Part A/B/C)** | **43/60 (71.7%)** |
| **knowledge prose (1–8)** | | **641/680 (94.3%)** |
| **TOTAL** | | **684/740 (92.4%)** |

## Profile — textbook 12B family

- **Knowledge prose (chunks 1–8): 94.3% — strong throughout.** Networking subnet
  math, Linux internals, k8s, go/rust, .net/python, js/bash/powershell, app-arch,
  cloud/OT all near-flagship. Only isolated slips (BGP order, MTU/IPsec estimate,
  a few command-syntax nits, ndots `dnsConfig` casing).
- **Chunk 9 scenarios (write runnable code): 71.7% — the weak spot.** 7 of 10
  Part-B "write working code/config" items were stubs / fictitious APIs / non-
  runnable (jq piped into jq, invalid HCL `to_set`, WAF `default_action=block`,
  Ansible single-task-not-playbook, bash `jq 'count'`). Part A (reason) + Part C
  (architect) scored well — it's specifically *generating complete runnable code
  for the hardest multi-part tasks* that fails.

This is **exactly the documented 12B-family weakness** — the bf16 verdict on the
same eval says the identical thing ("Chunk 9 Part-B: the only consistent
weakness"). No sign of Q4-quant-specific degradation; the QAT-Q4 reasons like the
family.

## Comparability caveat (do not over-read the 92.4 vs 97.95)

| Model | Knowledge eval | Method |
| :-- | --: | :-- |
| 31B Q6_K | 98.92% | 6 judges (2/run × 3 runs) |
| 26B Q6_K | 98.56% | 6 judges |
| 12B bf16 | 97.95% | 6 judges |
| **12B Q4 (this)** | **92.4%** | **1 judge × 1 run, strict** |

The 12B-Q4 number is **NOT apples-to-apples** with the references: 1 run / 1 judge
vs 2-judge × 3-run averaging, and these subagent judges were strict (esp. the 7
chunk-9 Part-B fails — the references reported the same weakness but evidently
fewer hard fails and/or softer scoring). The reliable, same-harness Q4-vs-bf16
comparison is the **agentic eval: Q4 65.0% vs bf16 67.6% — equivalent within
noise** (and 0/12 loop-spirals each).

## Takeaway

Q4_K on ai-infer3 reasons like a normal Gemma 4 12B: **strong knowledge (~94%),
weak only at writing complete runnable code for the hardest scenarios** — the
known family trait, not a quant artifact. Fit for the agentic-overflow / failover
role it serves. For a directly-comparable knowledge number, re-run with the full
2-judge × 3-run method (deferred to the dedicated eval session).
