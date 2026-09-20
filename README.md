# llm-evals

How we decide which model the homelab runs. Two things live here: **our own suites**
(knowledge, loop-detection, agentic, narrow-delivery) and **runs of external
benchmarks** against the same endpoints, under `external/`.

## The scores

**→ [DASHBOARD.md](DASHBOARD.md)** — one row per model: knowledge, loop, agentic,
serving engine, and a link to the evidence. It is the only place a number is
published.

What it says today, in one paragraph: the knowledge suite is **saturated at the top**.
Gemma 4 26B (98.56%), GLM-5.3-Flash (98.69%) and Gemma 4 31B (98.92%) sit inside
0.36 pp while the suite's own precision is 0.13 pp, so it **gates** builds and cannot
**rank** models — Hermes 4 14B's 92.75% is the evidence that it still separates a weak
model from a strong one. Ranking questions go to the external suites.

## Running one

| | |
|---|---|
| Which suite to run, and what actually works today | [external/RUNBOOK.md](external/RUNBOOK.md) — the `gate` / `rank` / `deep` tiers plus a per-suite status table |
| The knowledge suite end to end | [skills/judge-llm-eval/HOW-TO-DRIVE-EVAL.md](skills/judge-llm-eval/HOW-TO-DRIVE-EVAL.md) |
| Why the method is what it is | [METHODOLOGY.md](METHODOLOGY.md) |
| Where the raw runs are and what each one proves | [results/README.md](results/README.md) |

```bash
external/bin/eval-tier gate <model> http://<host>:<port>
```

**One run is the routine.** Three runs are for a new baseline — a new model, a new
architecture, a new quant family — because the run-to-run range is itself a signal.

## The suites

| Suite | What it measures | Size |
|---|---|---|
| knowledge (`infrastructure.md`, `development.md`, `architecture.md`, `scenarios.md`) | does the model solve the problem, across 9 chunked topic sets | 370 scored items, 740 points |
| `loop-detection/` | does it stop cleanly instead of spiralling, over-explaining or expanding the task | 12 scenarios per pass |
| `agentic/` | real tool use against a live exec host | 10 or 30 tasks |
| `narrow-delivery/` | obedience and functional verification on scoped delivery tasks | 9 tasks + exec tasks |
| `external/ds4-eval/` | deterministically graded reasoning and code cases, no judges | 142 cases |

The four knowledge files are the questions themselves, which is why they sit in the
root: 120 items on networking/Linux/Kubernetes/dev/OpenTofu/Ansible, 140 on
Go/Rust/.NET/Python/JS/Bash/PowerShell, 80 on application, on-prem, cloud and OT
architecture, and 10 cross-domain scenarios scored in three parts each.

Knowledge answers are judged by **two independent Opus judges per run**, scored
`mean(A, B)` per question, against a reference answer key that is explicitly *one
valid solution, not a contract*. `skills/judge-llm-eval/` holds the rubric, the key
and the deterministic code validators.

## License

MIT — use freely for evaluating any model.
