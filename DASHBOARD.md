# Model eval dashboard

One row per model, **latest generation only**. Superseded, invalid and unscored runs
live in [`results/_archive/`](results/_archive/README.md). A dash (**—**) means that
dimension was **not tested this generation**.

**Read the top of the table as a tie.** Gemma 4 26B (98.56%), GLM-5.3-Flash (98.69%)
and Gemma 4 31B (98.92%) sit inside 0.36 pp, and the knowledge suite's own precision
is 0.13 pp. It cannot rank them. It is still the right regression gate — it is
precise, and Hermes 4 14B scored 92.75% on it, so the bar is not automatic. Ranking
questions go to the external suites: [`RUNBOOK.md`](RUNBOOK.md).

The three dimensions:

- **Knowledge** — the 370-question chunked Q&A suite, Opus-judged, % of max points
  (740). Evidence: `results/<build>/`, method per directory in
  [`results/README.md`](results/README.md).
- **Loop** — loop/spiral resistance, 12 scenarios per pass, shown as **flags / total**
  (fewer = better). Auto-scored only (`is_spiral`, plus `empty_response` since
  2026-09-20); no judge-graded /120 exists. Evidence: `loop-detection/`.
- **Agentic** — tool-use task harness, % of max. Raw scores use different task counts
  (×/100, ×/300, ×/10) but **percentages are comparable**. Evidence: `agentic/`.

**Engine** = what served the shown result: **llama.cpp** (turbo/turboquant fork, GGUF)
or **vLLM** (GX10 container). `(fleet)` = the production LiteLLM fleet; `(GX10)` = the
DGX Spark playground.

| Model | Type | Quant | Engine | Knowledge ~400 | Loop (flags) | Agentic | Latest | Evidence |
|---|---|---|---|---|---|---|---|---|
| **Qwen3.6-27B** | dense | BF16 | vLLM (GX10) | **99.05%** | — | **100%** (10/10) | 2026-06-26 | [run](results/qwen36-27b-bf16-gx10/) · [vLLM cfg](configs/vllm-gx10-serving.md#-qwen36-27b-dense-bf16--validated-2026-06-26) |
| **Qwen3.5-122B-A10B** | MoE | Q5_K_M | llama.cpp (GX10) | **98.92%** | 0/24 ✅ | **87.7%** (263/300) | 2026-06-20 | [run](results/qwen35-122b-a10b-q5km-gx10/) ᶦ |
| **Gemma 4 31B** | dense | Q6_K | llama.cpp | **98.92%** ˢ | 0/9 ✅ ᵖ | — | 2026-05-16 | [verdict](results/gemma4-31b-q6k-turbo-128k-ai-infer2/verdict.md) |
| **Nemotron-3-Super-120B** | dense | UD-Q5 | llama.cpp (GX10) | **98.78%** | 0/24 ✅ | 57.3% (172/300) | 2026-06-21 | [run](results/nemotron-3-super-120b-udq5-gx10/) |
| **GLM-5.3-Flash** | MoE | UD-Q2_K_XL | llama.cpp (GX10) | **98.69%** (range 0.13 pp) | 4/36 ⚠️ ᴸ | — | 2026-09-20 | [verdict](results/glm5.3-flash-q2kxl-mtp-2x128k-gx10/verdict.md) |
| **Qwen3.6-35B-A3B** | MoE | Q5_K_M stock | llama.cpp (fleet) | **98.65%** ᵍ | 0/36 ✅ | 80% (8/10) | 2026-06-22 | [run](results/qwen36-35b-a3b-BF16-262k-gx10/) ᵍ |
| **Gemma 4 26B-A4B** | MoE | Q6_K | llama.cpp | **98.56%** | 0/12 ✅ | 58.0% (174/300) | 2026-06-18 | [verdict](results/gemma4-26b-q6k-458k-turbo4-v2-ai-infer2/verdict.md) |
| **GLM-4.7-Flash** | MoE | BF16 | vLLM (GX10) | **96.80%** | not measured ⁿ | 65.0% (195/300) ᵃ | 2026-07-09 | [verdict](results/glm-4.7-flash-vllm-gx10/VERDICT.md) ᵛ |
| **North-Mini-Code** | MoE | BF16 | vLLM (GX10) | ~96.6% ᶜ | not measured ⁿ | 70.0% (210/300) ᵃ | 2026-07-09 | [verdict](results/north-mini-code-1.0-vllm-gx10/VERDICT.md) ᵛ |
| **Gemma 4 E4B** (4B) | dense | BF16 | llama.cpp | 96.67% (range 1.62 pp) | 0/12 ✅ | **86.0%** (86/100) | 2026-04-15 | [verdict](results/gemma4-4b-e4b-bf16-10slots-turbo4-ai-infer2/verdict.md) |
| **Qwen3.5-9B** | dense | Q8_0 | llama.cpp | 95.7% ˣ | 9/12 ❌ | 74.0% (74/100) | 2026-04-18 | responses only |
| **Hermes4-14B** | dense | Q8 / q4kv | llama.cpp | 92.75% ʰ (range 0.95 pp) | 1/12 ⚠️ | 67.0% (67/100) | 2026-04-30 | [runs](results/hermes4-14b-q8-q4kv-2slot-65k-ai-infer2/) |
| **Qwen3.5-35B-A3B** | MoE | Q5_K_M | llama.cpp | 90.3% ˣ | — | — | 2026-03-21 | archived ˣ |
| **Gemma 4 12B** | dense | Q4 | llama.cpp | 89.9% ᑫ | 0/12 ✅ | 65.0% (195/300) | 2026-06-09 | [verdict](results/gemma4-12b-q4-ai-infer3/verdict.md) |

**Loop legend:** ✅ no flags · ⚠️ 1 flag or a known false positive · ❌ multiple real
spirals. Denominator = scenarios × passes (12, 24, 36 or 9-partial).

Fleet serving config lives in `homelab/ansible/inventory/model_profiles/llama_cpp/*.yaml`
— the files have been renamed since several of these runs, so match on model + quant.
GX10/vLLM launch config is in [`configs/vllm-gx10-serving.md`](configs/vllm-gx10-serving.md).
The GX10 GGUF runs (122B Q5, Nemotron, GLM-5.3) have no Ansible profile beyond the run
dir's `run-chunk.sh` — that box is a playground.

## vLLM vs llama.cpp — same model, both engines

How each model serves on **vLLM (GX10)** versus its **llama.cpp** serving. The question
was *serving viability + delta*, not which model to pick. **Knowledge deltas are
judge-confounded** (vLLM runs judged Opus-4.8, the 4.6 metered key was dry; 4.8 judges
stricter → treat ties as ties). **Agentic** cross-engine numbers are **date-confounded**
where the llama.cpp run predates vLLM 0.23's unified tool parser — flagged inline.

| Model | Knowledge vLLM | Knowledge llama.cpp | Agentic vLLM | Agentic llama.cpp | Loop | Notes | Read |
|---|---|---|---|---|---|---|---|
| **Gemma 4 26B-A4B** | **98.24%** (BF16) | 98.56% (Q6_K) | **88.7%** | 58.0% ⚠ᵈ | 0/0 tie ✅ | knowledge **tie**; agentic date-confound | [verdict](results/gemma4-26b-bf16-vllm-gx10/VERDICT.md) |
| **Gemma 4 12B** | **97.07%** (BF16) | 97.95% BF16 · 92.1% Q8 · 89.9% Q4 | **77.3%** | 65.0% (Q4) ⚠ᵈ | 0/0 tie ✅ | quant ladder: BF16 ≫ Q8 ≫ Q4 (~5–7 pt); engine tie | [verdict](results/gemma4-12b-bf16-vllm-gx10/VERDICT.md) |
| **Gemma 4 31B** | **98.38%** (BF16) | 98.92% (Q6_K) | **88.0%** | — (no prior) | 0/0 tie ✅ | family-highest knowledge, tie; first 31B agentic. Dense → ~4 tok/s | [verdict](results/gemma4-31b-bf16-vllm-gx10/VERDICT.md) |
| **Gemma 4 E4B** (4B) | **96.08%** (BF16) | 96.67% (BF16) | 67.7% | **86.0%** ⚠ᵉ | 0/0 tie ✅ | knowledge tie; **agentic −18 pt on vLLM** (elastic/centroid-head arch) | [verdict](results/gemma4-e4b-bf16-vllm-gx10/VERDICT.md) |
| **Qwen3.5-122B-A10B** | **96.60%** (Int4) | 98.92% (Q5_K_M) | 83.3% | 87.7% | 0/0 tie ✅ | Int4 ~2 pt back (judge-confounded); Q5-GGUF can't load on vLLM | [verdict](results/qwen35-122b-int4-vllm-gx10/VERDICT.md) |
| **Qwen3.6-35B-A3B** | 98.65% (BF16) | ~97.4% (Q5 stock) | — | 80% (8/10) | 0/0 tie ✅ | BF16 vLLM = the model's knowledge ceiling | [run](results/qwen36-35b-a3b-BF16-262k-gx10/) |
| **Qwen3.6-27B** | 99.05% (BF16) | — *(vLLM-only)* | 100% (10/10) | — | — | dense 27B, not in the llama.cpp fleet | [run](results/qwen36-27b-bf16-gx10/) |
| **Mistral Medium 3.5** | **97.93%** (Int4) | — *(not a fleet model)* | not run | — | **2/24** ⚠️ | 128B dense **~3 tok/s → too slow** (also on 0.24); campaign's first loop spirals | [verdict](results/mistral-medium-3.5-awq-vllm-gx10/VERDICT.md) |
| **Granite 4.1 30B** | **96.40%** (BF16) | — *(not a fleet model)* | not run | — | 0/24 ✅ | hybrid Mamba/Transformer **~3.4 tok/s → too slow** (unchanged on 0.24) | [verdict](results/granite-4.1-30b-vllm-gx10/VERDICT.md) |
| **GLM-4.7-Flash 30B-A3B** ᵛ | **96.80%** (BF16) | — *(vLLM-only)* | **65.0%** ᵃ | — | not measured ⁿ | **0.24-only unblock** — MoE **~20 tok/s**, fast + strong | [verdict](results/glm-4.7-flash-vllm-gx10/VERDICT.md) |
| **Cohere North-Mini-Code 30B-A3B** ᵛ | 93.11% raw / ~96.6% ᶜ | — *(vLLM-only)* | **70.0%** ᵃ | — | not measured ⁿ | **0.24-only unblock** — MoE **~27 tok/s** coding model; loop caveat ᶜ | [verdict](results/north-mini-code-1.0-vllm-gx10/VERDICT.md) |

**Takeaway:** vLLM serves these models at **no knowledge cost** (26B/35B tie or beat
llama.cpp same-judge; only the 122B *must* use Int4 — Q5-GGUF won't load — and pays
~2 confounded pt for it).

**⚠ᵈ date-confound:** the Gemma-26B llama.cpp agentic (58.0%) is a 2026-06-17 run on an
older harness/parser; the +30 pt vLLM gap is mostly tooling-era, not BF16-vs-Q6_K. It
needs a same-day llama.cpp re-run to attribute.

**⚠ᵉ E4B agentic:** the one clear vLLM regression — 18 pt *lower* on vLLM than
llama.cpp, and not a date-confound (the llama.cpp run is older). E4B's
elastic/centroid-head arch serves knowledge fine on vLLM but its tool-calling degrades.
Prefer llama.cpp for E4B agentic.

### vLLM 0.23 vs 0.24 — which of the owner's candidates can serve at all
**ᵛ = the `v0.24.0-aarch64-cu129-ubuntu2404` image is required.**

| Model | Arch | vLLM 0.23 | vLLM 0.24 |
|---|---|---|---|
| Mistral Medium 3.5 128B | dense (multimodal) | ✅ w/ `--config-format hf --limit-mm-per-prompt {image:0}` but **~3 tok/s** | still ~3 tok/s (dense-bound) |
| Granite 4.1 30B | hybrid Mamba/Transformer | ✅ but **~3.4 tok/s** | **still ~3.4 tok/s** (0.24 doesn't fix the Mamba path) |
| Cohere North-Mini-Code 30B-A3B | MoE | ⛔ `cohere2_moe` loader `KeyError` | ✅ **unblocked, ~27 tok/s** |
| GLM-4.7-Flash 30B-A3B | `Glm4MoeLite` | ⛔ `AssertionError` at init | ✅ **unblocked, ~20 tok/s** |
| Mistral Small 4 119B | MoE (multimodal, NVFP4) | ⛔ NVFP4-MoE `c10::Error` at init | 🟡 **arch fixed** (loads past init) but the 66 GB NVFP4 checkpoint **OOMs during load** on 121 GB UMA — a capacity wall, not arch |
| Mistral Small 3.2 24B | dense (multimodal) | ⛔ tokenizer garble (unsloth HF repo) / no consolidated for mistral-format | not re-run (repo/format issue, not a vLLM-version issue) |

**Bottom line.** Prefer **fast MoE (3–4B active)** on this box: the Gemma and Qwen
families on either image, plus GLM-4.7-Flash and North-Mini-Code on 0.24. What 0.24 does
not fix is the **dense/Mamba speed wall** and the **capacity wall** for the biggest
quants — both knowledge-strong, both unservable here.

## Provenance notes

- **ˢ Gemma 4 31B 98.92%** — scored by a single Opus judge per chunk, not the two-judge
  mean(A,B) that produced 98.56% (26B) and 98.69% (GLM-5.3). All three runs landed on
  exactly 732/740. The three-way tie at the top holds either way, but this figure is
  from the older method.
- **ᴸ GLM-5.3-Flash loop** — 4 flags over 3 passes × 12 scenarios. Three are LD11 in
  every pass and are a **false positive**: LD11 requires carrying a cumulative table
  across five batches, so consecutive paragraphs must repeat the accumulated rows. The
  fourth (LD1, pass 3, paragraphs 8 and 12 share 93% bigrams) is unreviewed. No
  reasoning spirals, no task-expansion creep; it stops cleanly on LD4, LD9 and LD10.
- **No Qwen build is scored under the current method.** Every Qwen directory —
  including the deployed fleet model `qwen36-35b-a3b-q5km-STOCK-2x128k-ai-infer2` — has
  responses but no `judge.json`, so **no head-to-head between the Qwen fleet and
  GLM-5.3-Flash exists**. The responses are on disk; the comparison costs one judging
  round, not another eval.
- **ᵍ Qwen3.6-35B-A3B** — knowledge 98.65% is the **GX10 vLLM BF16** run (runs 1–5);
  loop + agentic are from the llama.cpp BF16 runs. The **deployed fleet** serves
  `Q5_K_M stock` on llama.cpp, whose own deploy-eval scored ~97.4%. Treat 98.65% as the
  model's ceiling, not the fleet number.
- **ᶦ Qwen3.5-122B-A10B** — main-table knowledge (98.92%) is the Q5_K_M llama.cpp run;
  the **vLLM GPTQ-Int4** serving (2026-06-27) is judged **96.60%**. vLLM config:
  [vLLM cfg](configs/vllm-gx10-serving.md#-qwen35-122b-a10b-moe--gptq-int4-only-on-this-box).
- **ᵖ Gemma 4 31B loop** — a **partial** pass (9 scenarios) from the `q4km` build, not
  the `q6k` knowledge build. No agentic run exists.
- **ʰ Hermes4-14B** — 92.75% is the mean of three two-judge runs (92.43 / 92.43 /
  93.38). An earlier dashboard published run1's 92.43% and called runs 2–3 unjudged;
  all three carry a `judge.json`.
- **ˣ No artefact in this repo** — Qwen3.5-9B (responses only, never judged) and
  Qwen3.5-35B-A3B (responses in `_archive/qwen35-35b-a3b-q5km-2x262144-q4kv/`, never
  judged). Both numbers are pre-v2 single-judge figures carried forward; do not compare
  them tightly with anything above.
- **ᑫ Gemma 4 12B** — knowledge/agentic tested at **Q4** on ai-infer3; no Q4 serving
  profile exists (the fleet variant is Q8). 89.9% is the corrected 2-round re-judge and
  supersedes an earlier inflated 92.4%.
- **ᵛ GLM-4.7-Flash & North-Mini-Code** — 30B-A3B MoE reasoning models, **vLLM-only**
  (not fleet). Both were arch-blocked on vLLM 0.23 and unblocked on 0.24. Agentic is
  real 30-task tool use; GLM serves with the `glm47` parser on the stock image, Cohere
  needs `cohere_command4` with `cohere_melody` baked into a derived image (see
  [serving cfg](configs/vllm-gx10-serving.md)). Fast (~20 / ~27 tok/s) and ~96–97% on
  knowledge. Mid-pack: good mechanics, below the fleet's Qwen3.6-35B (89%).
- **ᵃ AG27 never ran.** In both the GLM-4.7-Flash and North-Mini-Code runs AG27 is
  recorded as `setup_failed` — the task never reached the model — yet it still
  contributes 0/10 to the published totals and counts among the 30 tasks. Excluding it:
  GLM **67.2%** (195/290), North-Mini-Code **72.4%** (210/290). The raw figures stay as
  the headline for comparability with the other 30-task runs; the corrected ones are
  the fairer read.
- **ⁿ GLM-4.7-Flash & North-Mini-Code loop — NOT MEASURED (withdrawn 2026-07-25).**
  Both previously showed "2/24 spirals". That figure was invalid: **all 24 generations
  per model are zero-byte** (`word_count: 0` throughout). The two `LD12-infinite-research`
  spiral flags were artifacts — LD12 is scored on the presence of a terminal phrase and
  an empty file trivially lacks it — and the other 22 empties counted as clean for the
  same vacuous reason. The run shows neither looping nor loop-resistance. See
  `loop-detection/results/{glm-4.7-flash,north-mini-code}/RUN-FAILED.md`. Re-running
  needs both models re-downloaded (purged from the GX10 at campaign close). This is the
  failure the `empty_response` flag now catches.
- **ᶜ North-Mini-Code knowledge** — **93.11% raw**; one of 3 runs lost an entire
  40-question chunk to an infinite reasoning loop (no answers → 0). Loop-excluded
  ≈ **96.6%**. That lost chunk — not the withdrawn loop run ⁿ — is the evidence for its
  loop-spiral tendency, and it is the model's real caveat: guard it with a step/token
  budget if it runs unattended.

## Reading a score straight from the data

```bash
# Knowledge, current method (merged two judges):
jq '{pct:.totals.percentage, score:"\(.totals.points)/\(.totals.max_points)"}' \
  results/<build>/run1/judge.json
# Knowledge, unmerged two judges (judge-A.json + judge-B.json) or per-chunk ratings:
jq -s 'map(to_entries[].value.points)|add as $p|{points:$p,max:(length*2),pct:($p/(length*2)*100)}' \
  results/<build>/run1/chunk*-ratings*.json
# Loop — flags per pass:
grep -h is_spiral loop-detection/results/<pass>/*-score.json | grep -c true
# Agentic — top-level percentage:
jq '{pct:.percentage, score:"\(.total_score)/\(.max_score)"}' agentic/results/<run>/agentic-*.json
```

`KNOWLEDGE-SUMMARY.md` or `judge-summary.md` in a run directory has the same numbers
already worked out, per chunk and per run.

---
*Closed cross-model verdicts (GX10 campaign, 31B-vs-26B, Q5_K_L-vs-Q6_K) are in
[`results/_archive/`](results/_archive/README.md). Why the method is what it is:
[`METHODOLOGY.md`](METHODOLOGY.md).*
