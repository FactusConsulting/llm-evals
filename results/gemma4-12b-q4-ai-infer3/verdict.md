# Verdict — Gemma 4 12B Q4_K turbo4 (ai-infer3)

**Knowledge/reasoning score: 89.9%** (665.0/740, 2-round average; 740 pts / 370 items;
re-judged 2026-06-09 in one consistent single-judge session alongside Q8 and 26B).
Generated against ai-infer3 `:8001` (12B **Q4_K** turbo4, 6×131k), judged with the
verbatim `judge-knowledge.py` rubric (pass=2 / partial=1 / fail=0) by Opus subagents.

> **Correction to the earlier 92.4%.** The first Q4 verdict (92.4%, 1 lenient judge
> round) over-stated the score. Re-judged in the same session as Q8/26B with 2 averaged
> rounds, the SAME responses score **89.9%**. The 92.4 ↔ 88.4–91.4 swing on identical
> text shows how noisy single-round judging is for Q4 specifically (see below).

## Per-chunk (2-round avg)

| Chunk | Topic | Score | rounds |
| :-- | :-- | --: | :-- |
| 1 | networking / linux | 74.5/80 (93.1%) | 72/77 |
| 2 | k8s / dev | 74.5/80 (93.1%) | 74/75 |
| 3 | opentofu / ansible | 68.0/80 (85.0%) | 68/68 |
| 4 | go / rust | 76.0/80 (95.0%) | 75/77 |
| 5 | .net / python | 77.0/80 (96.2%) | 77/77 |
| 6 | js / bash / powershell | 102.0/120 (85.0%) | 103/101 |
| 7 | app-arch / on-prem | 76.0/80 (95.0%) | 75/77 |
| 8 | cloud / OT | 74.5/80 (93.1%) | 72/77 |
| 9 | **scenarios (A/B/C)** | **42.5/60 (70.8%)** | 38/47 |
| **knowledge prose (1–8)** | | **622.5/680 (91.5%)** | |
| **TOTAL** | | **665.0/740 (89.9%)** | |

## Profile

- **Knowledge prose 91.5%** — ~2.7 pts below Q8 (94.2%). A small but consistent step
  down. Weakest at chunk 3 (opentofu/ansible, 85.0%) and chunk 6 (js/bash/ps, 85.0%).
- **Wide run-to-run spread (654–676).** Q4's answers sit in the pass/partial gray zone
  more often than Q8's (681/682, ~zero spread), so two independent Opus judges disagreed
  by up to 22 pts on identical text. The spread width is itself a quality signal: Q4 is
  more often "almost right" rather than decisively right.
- **Chunk-9 scenarios 70.8%** — the family Part-B weakness, comparable to Q8 (68.3%).

## Comparison & role

Same-session ranking: **26B 94.1% > Q8 92.1% > Q4 89.9%** — see
[`../12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md`](../12b-q4-vs-q8-vs-26b-knowledge-singlejudge.md).
Q4 carries a small (~2 pt) real knowledge penalty vs Q8 — but on the deterministic
**agentic eval** Q4 (65.0%) ≈ bf16 (67.6%), equivalent. Fit for the agentic
overflow/failover role ai-infer3 serves; the knowledge gap is immaterial there.
NOT comparable to the historical 6-judge references (this method runs ~4–5 pts stricter).
