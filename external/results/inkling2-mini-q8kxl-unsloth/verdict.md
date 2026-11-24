# Inkling 2 Mini — UD-Q8_K_XL on ai-infer2

**Verdict: level with Gemma 4 26B on quality for what ai-infer2 serves, five times
slower per request. Not adopted; ai-infer2 stays on Gemma 4 26B.**

## Run conditions

| | |
|---|---|
| Model | `thinkingmachines/Inkling-2-Mini` — 26.4B total, 3.4B active MoE, layers 6–17 looped three times (5.4B effective active) |
| Weights | `unsloth/Inkling-2-Mini-GGUF` rev `800c946d7b`, `Mainline_Support/Inkling-2-Mini-UD-Q8_K_XL` (the published NVFP4 experts, everything else BF16), `mmproj-F16` |
| Engine | Unsloth's llama.cpp release `b12649-mix-c7059d6` (binary reports `b12649-189f431bf`), CUDA 13 build |
| Host | ai-infer2, 2 × RTX 5060 Ti 16 GB, split 0.62 / 0.38 |
| Server | 2 slots × 131072, q4_0 KV, ubatch 128, flash attention, `--reasoning-effort none`, temperature 1.0 / top-k 0 / top-p 1.0 / min-p 0 (publisher's) |
| Serving profile | homelab `ansible/inventory/model_profiles/llama_cpp/inkling2-mini-q8kxl-unsloth.yaml` |
| Reference | Gemma 4 26B-A4B UD-Q6_K_XL, q4_0 KV, MTP, upstream b12410, thinking off — [`../gemma4-26b-q4kv-b12410/`](../gemma4-26b-q4kv-b12410/) |

The model always reasons. Its template turns `reasoning_effort` into a system line
(`Thinking effort level: 0` for `none`) and does not read `enable_thinking`; the model
card says the minimum effort "does not fully disable reasoning". Gemma ran with thinking
off throughout, so every comparison below is Inkling reasoning against Gemma not.

## Gate (`eval-tier gate`, 2026-11-23)

ds4-core, temperature 0, one run:

| Suite | Inkling 2 Mini | Gemma 4 26B |
|---|---|---|
| GPQA Diamond | 16/24 | 16/24 |
| SuperGPQA | 22/25 | 21/25 |
| AIME 2025 | 19/25 | 18/25 |
| GPQA Diamond (modified) | 0/1 | 1/1 |
| COMPSEC | 16/17 | 15/17 |
| **Total** | **73/92** | **71/92** |

Two cases is inside one run's noise. 17 Inkling cases were forced to close at the length
or time limit, mostly AIME.

Loop detection: 0 spirals, 1 empty response (LD7) of 12 — 1/12 on the dashboard's
flag count. Gemma: 1 spiral of 12.

## AI Regelkompas extraction (ai-compliance-dk `tests/artefacts/ai_eval.py`)

Danish field extraction from 40 fictional project descriptions, through the app's
sidecar. One run per variant; Gemma is the median of three. Full record in
ai-compliance-dk `docs/qa/AI-EVAL.md`.

| | Gemma 4 26B | Inkling, 2000 tok / 75 s | Inkling, 4000 tok / 90 s | Inkling, no reasoning (prefill) |
|---|---|---|---|---|
| Precision | 93 % | 96 % * | 92 % | 88 % |
| Recall | 95 % | 100 % * | 96 % | 91 % |
| mustNot breaches | 0 | 0 * | 0 | 2 |
| Failed extractions | 0 | 19/40 | 3/40 | 0 |
| Median extract / draft | 10 s / 5 s | 40 s / 32 s | 50 s / 34 s | 12.5 s / 9 s |

\* only the 21 that completed. At the app's original budget the reasoning ran out of
tokens before the JSON; with the most Cloudflare's 100 s allows, quality matches Gemma
and the remaining failures are the time limit. With reasoning prevented (an assistant
turn prefilled with `{`), it answers as fast as Gemma and worse.

## Speed (ai-infer2)

| | Inkling 2 Mini (Unsloth build) | Gemma 4 26B |
|---|---|---|
| Prompt processing, 14k-token prompt | 903 tok/s | ~3,600 tok/s (27k prompt) |
| Generation | 42–45 tok/s | 28–35 tok/s |
| Reasoning per Regelkompas extraction | median ~1,950 tokens, p90 ~3,000 | none |

Upstream llama.cpp (b12653) reached 160 tok/s prompt and 10–20 tok/s generation, and
could not hold Q8 beside a useful window: its flash attention has no banded path for a
quantised KV cache, so the compute buffer grows with window × ubatch. Unsloth's DSpark
drafter needed a smaller window to fit and measured 46–47 tok/s on structured output,
28 tok/s on prose. vLLM on the same pair of cards is reported at ~122 tok/s generation
with a 100k window ([model discussion #36](https://huggingface.co/thinkingmachines/Inkling-2-Mini/discussions/36));
not measured here.

## Not measured

Knowledge suite (needs judges), rank tier (tau2, BFCL), agentic, vision, long context —
the areas where the publisher reports Inkling's lead.
