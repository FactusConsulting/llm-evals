# Gemma 4 12B vs 26B-A4B — agentic + loop-detection head-to-head

**Date:** 2026-06-08
**Host:** `ai-infer2` — 2× RTX 5060 Ti 16 GB. **Both models benchmarked on the SAME idle box**
(see "Why not ai1" below). llama.cpp turbo build, Q6_K / bf16, turbo4 KV.
**Question:** is Gemma 4 **12B** better at *agentic workflows* than **26B-A4B**?

## TL;DR — yes, 12B wins on agentic execution

| Suite | 12B bf16 | 26B-A4B Q6_K | Winner |
|---|--:|--:|---|
| **Agentic** (mean of 5 runs, /30 tasks) | **67.6 %** (25.2/30 verified) | 59.0 % (25.6/30 verified) | **12B** (+8.6 pp) |
| **Loop-detection** (spiral incidents, 5 runs) | **0** | 1 (run1, REPEATED_ACTION) | **12B** |
| Speed (per agentic run) | ~44 min | **~15 min** | 26B (~3×, MoE) |

- **Agentic:** 12B scores higher and it's robust — every 12B run ≥ 64 %, every 26B run ≤ 64 %
  (runs: 12B `64,64,66,71,74`; 26B `56,57,58,61,64`). Both **verify ~25/30 tasks**, so the gap is
  **quality of execution** (the score = completion + efficiency + recovery + quality), not raw
  task-completion. 12B does the tasks *better*.
- **Loop-detection:** 12B never spiralled across 5×10 scenarios; 26B spiralled once (an
  error-handling task, `REPEATED_ACTION`).
- **26B's advantages** lie elsewhere: **knowledge** (98.56 % vs 12B's 97.95 % on the knowledge
  eval — see `results/gemma4-12b-bf16-65k-turbo4-ai-infer2/`) and **raw speed** (MoE, ~4B active →
  ~3× faster per run).

**Takeaway:** for **agentic task-execution → 12B**; for **knowledge-heavy work + throughput → 26B**.
The agentic eval (direct measure) and the knowledge eval (Q&A) genuinely point different ways —
they measure different things.

## Per-run detail

### Agentic (harness.py --all, 30 tasks, programmatically verified)
| run | 12B % (verified) | 26B % (verified) |
|--:|--:|--:|
| 1 | 63.7 (24/30) | 57.3 (25/30) |
| 2 | 63.7 (24/30) | 57.7 (26/30) |
| 3 | 66.3 (24/30) | 63.7 (26/30) |
| 4 | 70.7 (27/30) | 55.7 (26/30) |
| 5 | 73.7 (27/30) | 60.7 (25/30) |
| **mean** | **67.6 (25.2/30)** | **59.0 (25.6/30)** |

### Loop-detection (run-eval.sh, 10 scenarios LD1–LD10, automated spiral/termination scoring)
- 12B: spiral count 0/12 on all 5 runs.
- 26B: 1/12 on run1 (REPEATED_ACTION on an error-message task), 0/12 on runs 2–5.
- (Automated metric only; full Completion/Accuracy/Economy dimensions need the Opus judge — not run.)

## Method & a methodology lesson

- **Both models on the SAME idle `ai-infer2`**, run sequentially. The harness is an HTTP client
  (`LLAMA_API_KEY` from the host's `/etc/llama-api-key`); 12B served as `gemma4-12b`, 26B served
  under a non-production alias `gemma4-26b-eval` so production traffic (LiteLLM LB + openclaw)
  would **not** route to it and pollute the run.
- **Why not ai1 (the first attempt):** the initial design ran 26B on `ai-infer1` (production).
  Under concurrent openclaw/LiteLLM load every agentic task hit the harness's 300 s model-call
  timeout → `0 steps` → all 5 runs invalid, and loop-detection dirs came back empty. **Lesson:
  never benchmark agentic ability on a box serving production** — contention masquerades as model
  failure. We re-ran both on the idle box; GPU util ~35–40 % confirmed 26B was actually generating.
- The harness model-call timeout was tightened **300 s → 120 s** (`agentic/harness.py`) so a failing
  task fails fast instead of burning 5 min; on an idle box this makes 5× runs tractable without
  cutting legitimately-completing tasks.

Harness scripts used: `agentic/harness.py --all`, `loop-detection/run-eval.sh`.
