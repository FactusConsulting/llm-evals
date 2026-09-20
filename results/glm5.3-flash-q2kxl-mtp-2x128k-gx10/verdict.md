# Verdict — GLM-5.3-Flash UD-Q2_K_XL on gx10

**Date**: 2026-09-20
**Host**: gx10 (DGX Spark / GB10, 121 GiB unified)
**Endpoint**: `http://192.168.2.173:30000` (no auth), alias `glm5.3-flash`

## Setup under test

| | |
|---|---|
| build_info | `b11036-86ebfef2c` (TheTom/llama-cpp-turboquant, GLM-5.3 PR pin) |
| chat template sha256 | `d332fd5766d800fb` |
| model | `GLM-5.3-Flash-GGUF/UD-Q2_K_XL`, 4 shards, 102 GB on disk |
| context | 262144 total / 2 slots = **131072 per slot** |
| KV cache | `q4_0` |
| speculative decoding | `--spec-type draft-mtp --spec-draft-n-max 2`, no draft model |
| memory | 116 of 121 GiB used, 4 GiB free |
| sampling | temperature 0.1, top_p 0.95, max_tokens 49152 |

## TL;DR

- **Mean across 3 runs: 98.69%** (730.3/740), range **0.13 pp**
- Analysis and architecture are **100% in every run**; every point lost is in written code
- One dominant, reproducible defect: **HCL/Go syntax compressed onto one line with commas**
- Throughput: **238-246 tok/s prefill, 22.2-22.8 tok/s generation**, MTP acceptance 0.56-0.62
- Loop detection: **11 of 12 clean**, and the twelfth flag is the detector misreading correct state tracking
- **Recommendation: keep it.** It matches the strongest thing the fleet has ever scored,
  at 131k per slot on a box that previously could not hold a model this size.

## Score

See `judge-summary.md` for the full tables. Headline:

| | run1 | run2 | run3 | Mean |
|---|---|---|---|---|
| % | 98.65 | 98.78 | 98.65 | **98.69** |
| Part A / C (chunk 9) | 100 / 100 | 100 / 100 | 100 / 100 | **100 / 100** |
| Part B (chunk 9) | 75.0 | 80.0 | 65.0 | **73.3** |

## What the quant costs

Q2_K_XL is a 2-bit quant of a model whose f16 weights would not fit on this box at all.
The damage it does is narrow and visible:

1. **Syntax compression.** The model writes `variable "storage" { type = string, default = "500Gi" }`
   and `import ( "context", "time", )`. Both are rejected by their own tools. The intent,
   the resource schema and the logic are right; the separators are not. This is the single
   largest score contributor and it hit SC4-B and SC9-B in all three runs.
2. **Exact identifiers drift.** `AddFilter` for `AddEndpointFilter`, `ICustomRule` for
   `IScriptRule`, `pods/logs` for `pods/log`, `-generate-resource-out` for
   `-generate-config-out`, several ATT&CK-for-ICS technique IDs. The prose around them is
   correct — it is the token-exact name that slips.
3. **Cosmetic token leaks.** A single Chinese word ("横向") appeared mid-English-sentence in
   SC9-A in all three runs, and a few proper nouns garbled ("MagP" for Maglev). Judges did
   not score these; they are the clearest fingerprint of the 2-bit quant.

What the quant does **not** cost: reasoning, architecture, trade-off analysis, knowledge
breadth. Chunks 1, 4 and 7 were 100% in every run.

## Practical consequence

Use it for analysis, review, design and explanation without reservation. When it writes
**HCL or Go**, run the formatter before trusting the output — `tofu fmt` catches the exact
failure class, every time, in under a second. That is a cheap guard, not a blocker.

## Throughput

Measured from `llama-server` `print_timings` during the eval:

| | |
|---|---|
| prompt eval | 238-246 tok/s (~4.1 ms/token) |
| generation | 22.2-22.8 tok/s (~44.8 ms/token) |
| MTP draft acceptance | 0.56-0.62 under load (0.74 measured in isolation) |

Prefill at ~240 tok/s is the number to remember; an earlier 150 tok/s reading was taken
while the box was serving real work on the other slot.

## Judged twice

Round 1 exposed a hole in the suite, not in the model: `answers/chunk7-8-architect.md`
covered only Q1-12 of its four sections, so 32 of the 80 questions in chunks 7 and 8 had
no reference and were scored from judge knowledge. The key was filled in (80 answers now,
up from 48, exact identifiers checked against primary sources) and chunks 7 and 8 were
rescored from scratch by two fresh judges per run.

Result: **-0.09 pp on the mean, and the range halved from 0.27 to 0.13 pp.** Two final
ratings moved across 240 rescored questions, and only one of them (run2 AA19, a missed
enumerated sub-part) was among the 32 that had lacked a reference. The missing key was not
inflating anything. `run*/judge-round1.json` holds the pre-key scoring.

## Comparison

Same methodology (`judge-llm-eval/2.0`, two Opus judges, mean(A,B)):

| Model | Mean | Range |
|---|---|---|
| **GLM-5.3-Flash UD-Q2_K_XL (gx10)** | **98.69%** | 0.13 pp |
| Gemma 4 31B Q6_K turbo 128k (ai-infer2) | 98.92% | — |
| Gemma 4 26B Q6_K turbo v2 (ai-infer2) | 98.56% | 0.67 pp |
| Gemma 4 4B E4B BF16 (ai-infer2) | 96.67% | 1.62 pp |
| Hermes 4 14B Q8 (ai-infer2) | 92.75% | 0.95 pp |

+0.13 pp over the 26B baseline and -0.23 pp under the 31B. Both are inside the noise
floor the procedure sets (deltas under 1 pp are noise), so the honest reading is a
**three-way tie at the top** — and GLM gets there with the tightest run-to-run range of
any model in the set.

**No comparison with the Qwen fleet is possible yet.** Every Qwen directory in `results/`
— including the current fleet model `qwen36-35b-a3b-q5km-STOCK-2x128k-ai-infer2` — has
response files but **no `judge.json`**. They were never scored under this methodology.
Judging Qwen3.6's existing responses would cost one more round of six judges and would
answer the head-to-head properly; the responses are already on disk.

## Run conditions — read this before comparing

**run2 shared the box with real work on slot 1.** chunk6 took 77 min and chunk9 60 min,
against 19-20 and 23-27 min in run1 and run3. That is slot contention, not model
variation, and it did not hurt the score (run2 is the highest of the three) — but it is a
variable that was present, and the procedure warns against it for a reason.

Total: 3 runs x 9 chunks, serial, 00:09 to 07:40 = 451 min. 27 of 27 responses, 0 failures,
no truncated or empty files.

## Loop detection

12 scenarios, one pass, same endpoint (`loop-detection/run-glm53-gx10.sh`).

| | |
|---|---|
| Clean | 11 of 12 |
| Flagged | LD11 only |
| Word counts | 140-755 (no scenario ran long) |

The LD11 flag (`REPEATED_PARAGRAPH: paragraphs 1 and 2 share 100% bigrams`) is a **false
positive**. LD11 is the state-tracking scenario: the model must carry a cumulative table
across five batches without dropping or duplicating rows. It did exactly that, so
consecutive paragraphs necessarily repeat the accumulated rows. The detector reads correct
behaviour as repetition.

So: **no reasoning spirals, no task-expansion creep, no n-gram loops.** It stops cleanly,
including on LD4 and LD9 where no stopping point is given (298 and 495 words) and LD10
where it must stop after three attempts (140 words).

## Decision

Keep gx10 on `glm5.3-flash-q2kxl-128k-mtp-gb10`. Do not spend the downtime chasing a
higher quant: Q2_K_XL already ties the fleet's best score, and the 121 GiB pool has 4 GiB
of headroom left — there is nowhere for a bigger quant to go without cutting context.

Open question, deliberately left open: **flash-attention on GLM** is marked UNSETTLED in
the model card. It was on for this eval.
