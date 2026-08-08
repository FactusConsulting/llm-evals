# Verdict — Gemma 4 12B bf16 turbo4 (ai-infer2)

**Score: 97.95%** (mean of 3 runs; 6 Opus judges, 2 per run; 370 questions/run)

| Run | Score |
| :-- | :-- |
| run1 | 97.43% |
| run2 | 98.18% |
| run3 | 98.24% |
| **mean** | **97.95%** |

Run-spread 0.81pp — stable.

## Comparison to baselines

| Model | Score | Δ vs 12B |
| :-- | :-- | :-- |
| Gemma 4 31B Q6_K turbo | 98.92% | +0.97pp |
| Gemma 4 26B Q6_K turbo | 98.56% | +0.61pp |
| **Gemma 4 12B bf16 turbo** | **97.95%** | — |

The 12B sits ~0.6pp below the 26B and ~1.0pp below the 31B — within ~1pp of both
flagships despite having less than half their parameter count.

## Qualitative finding (consistent across all 6 judges)

- **Chunks 1–8 (knowledge prose): technically strong throughout** — networking,
  linux, k8s, opentofu/ansible, go/rust, .net/python, js/bash/powershell,
  app-arch, cloud/OT. Only isolated factual slips (e.g. K11 invented
  `kube-node-nginux`, B7/B11 bash redirection/`$!` semantics, A8 ansible-vault
  `encrypt_string`).
- **Chunk 9 Part-B (write working code): the only consistent weakness.** Recurring
  pattern: stubs with placeholder comments ("# Mock logic", "# Add rules…"),
  fictitious APIs (`gobreaker.NewBreaker`/`*gobreaker.Breaker` — real API is
  `NewCircuitBreaker`/`*CircuitBreaker`), literal `...` placeholders in HCL,
  incomplete WAFv2 rules. Part A (diagnosis) and Part C (design) reasoning were
  uniformly solid.

**Takeaway:** Gemma 4 12B *knows* the material at near-flagship level; the gap to
26B/31B is almost entirely in producing complete, runnable code for the hardest
multi-part scenarios. For knowledge/reasoning at this size + speed it is excellent.

## Config
- Model: `ggml-org/gemma-4-12B-it-GGUF` / `gemma-4-12B-it-bf16.gguf` (highest quant)
- Engine: llama.cpp turbo (b8753 + turboquant patch), turbo4 KV, ctx 65536, dual RTX 5060 Ti
- Endpoint: ai-infer2:8001, alias `gemma4-12b`, thinking on (reasoning_content)
