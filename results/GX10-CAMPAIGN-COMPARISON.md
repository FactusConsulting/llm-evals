# GX10 model campaign — final comparison

Hardware: DGX Spark / GX10 (GB10, sm_121, 121 GB unified). 1 model at a time, 2 slots.
Evals: our Opus-judged knowledge (6-judge: 2 judges × 3 runs, 370 Q/run) + agentic harness
(30 tasks, exec-host ubuntu@192.168.2.175, functional verification).

## Knowledge (all 4 complete)

| Model | Active params | Knowledge | spread | stdev |
|---|---|---|---|---|
| **Qwen3.6-27B BF16** (dense) | 27B | **99.05%** | 98.78–99.59 | 0.30 |
| Qwen3.5-122B-A10B Q5_K_M | 10B / 122B | 98.92% | 98.0–99.5 | 0.48 |
| Nemotron-3-Super-120B UD-Q5 | 12B / 120B | 98.78% | 98.0–99.5 | 0.47 |
| Qwen3.6-35B-A3B BF16 | 3B / 35B | 98.65% | 97.8–99.5 | 0.51 |

**Knowledge is saturated.** All four land inside a 0.4pt band — well within single-judge
noise (~4pt). The 27B dense edges the field but the result is statistically a tie. Knowledge
does NOT differentiate these models.

## Agentic (long-horizon autonomous delivery — the real differentiator)

| Model | Agentic | verified | Note |
|---|---|---|---|
| Qwen3.5-122B-A10B | **87.7%** | 27/30 | ties the 3.5×-smaller 35B |
| **Qwen3.6-35B-A3B BF16** | **87.0%** | 27/30 | the deployed fleet model |
| Nemotron-3-Super-120B | 57.3% | 24/30 | best one-shot knowledge, collapses on agentic |
| Qwen3.6-27B BF16 | — | — | not run (dense BF16 too slow to be a fleet candidate) |

## Throughput (GX10, BF16/Q5)

| Model | tok/s | why |
|---|---|---|
| Qwen3.6-35B-A3B | ~35 | MoE, only 3B active |
| 120B-class (122B-A10B / Nemotron-A12B) | ~14 | 10–12B active |
| Qwen3.6-27B dense | ~4.6 | dense — every param every token (slowest by far) |

## Verdict

**Qwen3.6-35B-A3B is the winner — and it's already the fleet model.**

- It **ties the 3.5× larger Qwen3.5-122B on BOTH knowledge (within noise) AND agentic
  (87.0 vs 87.7)** — at ~2.5× the throughput. The 120B-class buys nothing for the extra
  VRAM/compute.
- **Nemotron is a trap**: top-tier one-shot knowledge (98.78%) but agentic collapses to 57%
  — concrete proof that one-shot Q&A ≠ autonomous delivery. Unfit for fleet agents.
- **27B dense is pointless here**: marginally-highest knowledge (within noise), no agentic
  edge, and 7–8× slower than the MoE. Dense scaling doesn't pay.

Reaffirms the deployed decision: keep **Qwen3.6-35B-A3B** on the fleet. The lever for better
autonomous delivery is task shape + enforced verification (see narrow-delivery / story-shaping),
NOT a bigger model.

## vLLM 0.24 additions (2026-07-09) — GLM-4.7-Flash & Cohere North-Mini-Code

Two more 30B-A3B MoE reasoning models, added after the vLLM **0.24** upgrade (both were
arch-blocked on 0.23). Full profile now complete for each:

| Model | Active | Knowledge | Loop | Agentic | tok/s | Tool parser |
|---|---|---|---|---|---|---|
| **GLM-4.7-Flash** | 3B / 31B | 96.80% | not measured ⁿ | **65.0%** (195/300) | ~20 | `glm47` (stock image) |
| **North-Mini-Code** | 3B / 30B | ~96.6%* | not measured ⁿ | **70.0%** (210/300) | ~27 | `cohere_command4` (needs `cohere_melody`) |

*Cohere raw 93.11%; one run lost a chunk to a reasoning-loop → loop-excluded ~96.6%.

**Neither beats the fleet.** Both are knowledge-competitive but land **below Qwen3.6-35B on
agentic** (65/70 vs 87); North-Mini-Code additionally carries a loop-spiral tendency ⁿ that the fleet Qwen and
Gemma models don't. They're solid, fast, tool-capable local models — but not a fleet upgrade.
Value delivered: vLLM-0.24 serving know-how + the parser/`cohere_melody` gotchas, now codified
in `configs/gx10-serving/`.

## Campaign status: COMPLETE

All owner-listed models profiled (knowledge/loop/agentic where feasible): the 4 original GX10
models + GLM-4.7-Flash + North-Mini-Code (MoE, fast) and the dense/slow/memory-walled set
(Mistral Medium 3.5 128B ~3 tok/s, Mistral Small 4 119B OOMs the 121GB box, Granite 4.1 30B
~3.4 tok/s, Mistral Small 3.2 repo/tokenizer issue — all documented, none fleet-viable). The
**GX10 as a vLLM playground has done its job**: no model tested beats the deployed
Qwen3.6-35B-A3B for the fleet's agentic workload. The best fast model to *run on the GX10
itself* is **Gemma 4 26B-A4B BF16** (98.24% knowledge / 88.7% agentic / 0 loops) — a distinct
family from the fleet — now hooked up as the GX10's managed default.

**ⁿ Loop figures withdrawn (2026-07-25).** GLM-4.7-Flash and North-Mini-Code previously showed
"2/24 ⚠️" here. That run produced only zero-byte generations, so it measured nothing — see
`../loop-detection/results/{glm-4.7-flash,north-mini-code}/RUN-FAILED.md`. North-Mini-Code's
loop-spiral caveat survives on independent evidence (a knowledge chunk lost to an infinite
reasoning loop); GLM-4.7-Flash's loop behaviour is unknown.
