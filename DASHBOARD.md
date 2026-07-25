# Model eval dashboard

One row per model, **latest generation only**. Older/superseded runs are moved to `results/_archive/` and not shown here. A dash (**—**) means that dimension was **not tested this generation**.

Three quality dimensions:
- **Knowledge** — the ~400-question chunked Q&A suite, Opus-judged (% of max points). Driver: `results/` + `judge-knowledge.py`.
- **Loop** — loop/spiral resistance, 12 scenarios per run. Shown as **spirals / total** (fewer = better). All current runs are **auto-scored only** (`is_spiral`); no judge-graded /120 exists yet. Driver: `loop-detection/`.
- **Agentic** — real tool-use task harness (% of max). Driver: `agentic/`. Raw scores use different task counts (×/100 vs ×/300 vs ×/10) but **percentages are comparable**.

**Engine** = what actually served the model for the shown result: **llama.cpp** (turbo-fork, GGUF) or **vLLM** (GX10 container). `(fleet)` = the production LiteLLM fleet; `(GX10)` = the DGX Spark playground.

| Model | Type | Quant | Engine | Knowledge ~400 | Loop (spirals) | Agentic | Latest | Config |
|---|---|---|---|---|---|---|---|---|
| **Qwen3.6-27B** | dense | BF16 | vLLM (GX10) | **99.05%** | — | **100%** (10/10) | 2026-06-26 | [vLLM cfg](configs/vllm-gx10-serving.md#-qwen36-27b-dense-bf16--validated-2026-06-26) |
| **Qwen3.5-122B-A10B** | MoE | Q5_K_M | llama.cpp (GX10) | **98.92%** | 0/24 ✅ | **87.7%** (263/300) | 2026-06-20 | [GX10 run](results/qwen35-122b-a10b-q5km-gx10/) ᶦ |
| **Gemma 4 31B** | dense | Q6_K | llama.cpp | **98.92%** | 0/9 ✅ ᵖ | — | 2026-05-16 | [profile](../homelab/ansible/inventory/model_profiles/gemma4-31b-q6k-turbo.yml) |
| **Nemotron-3-Super-120B** | dense | UD-Q5 | llama.cpp (GX10) | **98.78%** | 0/24 ✅ | 57.3% (172/300) | 2026-06-21 | [GX10 run](results/nemotron-3-super-120b-udq5-gx10/) |
| **Qwen3.6-35B-A3B** | MoE | Q5_K_M stock | llama.cpp (fleet) | **98.65%** ᵍ | 0/36 ✅ | 80% (8/10) | 2026-06-22 | [profile](../homelab/ansible/inventory/model_profiles/qwen3.6-35b-a3b-q5km-stock.yml) |
| **Gemma 4 26B-A4B** | MoE | Q6_K | llama.cpp | **98.56%** | 0/12 ✅ | 58.0% (174/300) | 2026-06-18 | [profile](../homelab/ansible/inventory/model_profiles/gemma4-26b-q6k-turbo.yml) |
| **GLM-4.7-Flash** | MoE | BF16 | vLLM (GX10) | **96.80%** | 2/24 ⚠️ | 65.0% (195/300) | 2026-07-09 | [verdict](results/glm-4.7-flash-vllm-gx10/VERDICT.md) ᵛ |
| **North-Mini-Code** | MoE | BF16 | vLLM (GX10) | ~96.6% ᶜ | 2/24 ⚠️ | 70.0% (210/300) | 2026-07-09 | [verdict](results/north-mini-code-1.0-vllm-gx10/VERDICT.md) ᵛ |
| **Gemma 4 E4B** (4B) | dense | BF16 | llama.cpp | 96.67% | 0/12 ✅ | **86.0%** (86/100) | 2026-04-15 | [profile](../homelab/ansible/inventory/model_profiles/gemma4-4b-bf16-turbo.yml) |
| **Qwen3.5-9B** | dense | Q8_0 | llama.cpp | 95.7% | 9/12 ❌ | 74.0% (74/100) | 2026-04-18 | — |
| **Hermes4-14B** | dense | Q8 / q4kv | llama.cpp | 92.43% ʳ | 1/12 ⚠️ | 67.0% (67/100) | 2026-04-30 | [profile](../homelab/ansible/inventory/model_profiles/hermes4-14b-q8-turbo.yml) |
| **Qwen3.5-35B-A3B** | MoE | Q5_K_M | llama.cpp | 90.3% ʳ | — | — | 2026-03-21 | — |
| **Gemma 4 12B** | dense | Q4 | llama.cpp | 89.9% | 0/12 ✅ | 65.0% (195/300) | 2026-06-09 | [profile](../homelab/ansible/inventory/model_profiles/gemma4-12b-q8-turbo.yml) ᑫ |

**Loop legend:** ✅ no spirals · ⚠️ 1 spiral · ❌ multiple spirals. Denominator = scenarios × runs (varies: 12, 24, 36, or 9-partial).

## vLLM vs llama.cpp — same model, both engines

The GX10 vLLM campaign: how each model serves on **vLLM (GX10)** vs its **llama.cpp**
serving. Goal is *serving-viability + delta*, not picking a model. **Knowledge deltas
are judge-confounded** (vLLM runs judged Opus-4.8, the 4.6 metered key is dry; 4.8 runs
stricter → treat ties as ties). **Agentic** cross-engine numbers are **date-confounded**
where the llama.cpp run predates vLLM 0.23's unified tool-parser — flagged inline.

| Model | Knowledge vLLM | Knowledge llama.cpp | Agentic vLLM | Agentic llama.cpp | Loop | Notes | Read |
|---|---|---|---|---|---|---|---|
| **Gemma 4 26B-A4B** | **98.24%** (BF16) | 98.56% (Q6_K) | **88.7%** | 58.0% ⚠ᵈ | 0/0 tie ✅ | knowledge **tie**; agentic date-confound | [verdict](results/gemma4-26b-bf16-vllm-gx10/VERDICT.md) |
| **Gemma 4 12B** | **97.07%** (BF16) | 97.95% BF16 · 92.1% Q8 · 89.9% Q4 | **77.3%** | 65.0% (Q4) ⚠ᵈ | 0/0 tie ✅ | quant ladder: BF16 ≫ Q8 ≫ Q4 (~5–7 pt); engine tie | [verdict](results/gemma4-12b-bf16-vllm-gx10/VERDICT.md) |
| **Gemma 4 31B** | **98.38%** (BF16) | 98.92% (Q6_K) | **88.0%** | — (no prior) | 0/0 tie ✅ | family-highest knowledge, tie; first 31B agentic. Dense → slow ~4 tok/s | [verdict](results/gemma4-31b-bf16-vllm-gx10/VERDICT.md) |
| **Gemma 4 E4B** (4B) | **96.08%** (BF16) | 96.67% (BF16) | 67.7% | **86.0%** ⚠ᵉ | 0/0 tie ✅ | knowledge tie; **agentic −18 pt on vLLM** (E4B elastic/centroid-head arch) | [verdict](results/gemma4-e4b-bf16-vllm-gx10/VERDICT.md) |
| **Qwen3.5-122B-A10B** | **96.60%** (Int4) | 98.92% (Q5_K_M) | 83.3% | 87.7% | 0/0 tie ✅ | Int4 ~2pt back (judge-confounded); Q5-GGUF can't load on vLLM | [verdict](results/qwen35-122b-int4-vllm-gx10/VERDICT.md) |
| **Qwen3.6-35B-A3B** | 98.65% (BF16) | ~97.4% (Q5 stock) | — | 80% (8/10) | 0/0 tie ✅ | BF16 vLLM = the model's knowledge ceiling | [run](results/qwen36-35b-a3b-BF16-262k-gx10/) |
| **Qwen3.6-27B** | 99.05% (BF16) | — *(vLLM-only)* | 100% (10/10) | — | — | dense 27B, not in the llama.cpp fleet | [run](results/qwen36-27b-bf16-gx10/) |
| **Mistral Medium 3.5** | **97.93%** (Int4) | — *(not a fleet model)* | not run | — | **2/24** ⚠️ | 128B dense **~3 tok/s → too slow** (also on 0.24); campaign's first loop spirals | [verdict](results/mistral-medium-3.5-awq-vllm-gx10/VERDICT.md) |
| **Granite 4.1 30B** | **96.40%** (BF16) | — *(not a fleet model)* | not run | — | 0/24 ✅ | hybrid Mamba/Transformer **~3.4 tok/s → too slow** (unchanged on 0.24) | [verdict](results/granite-4.1-30b-vllm-gx10/VERDICT.md) |
| **GLM-4.7-Flash 30B-A3B** ᵛ | **96.80%** (BF16) | — *(vLLM-only)* | **65.0%** | — | **2/24** ⚠️ | **0.24-only unblock** — MoE **~20 tok/s**, fast + strong, adopt-worthy | [verdict](results/glm-4.7-flash-vllm-gx10/VERDICT.md) |
| **Cohere North-Mini-Code 30B-A3B** ᵛ | 93.11% raw / ~96.6% ᶜ | — *(vLLM-only)* | **70.0%** | — | **2/24** ⚠️ | **0.24-only unblock** — MoE **~27 tok/s** coding model; loop-spiral caveat | [verdict](results/north-mini-code-1.0-vllm-gx10/VERDICT.md) |

**⚠ᵈ date-confound:** the Gemma-26B llama.cpp agentic (58.0%) is a 2026-06-17 run on an
older harness/parser; the +30 pt vLLM gap is mostly tooling-era, not BF16-vs-Q6_K. Needs
a same-day llama.cpp re-run to attribute. **Takeaway so far:** vLLM serves these models at
**no knowledge cost** (26B/35B tie or beat llama.cpp same-judge; only the 122B *must* use
Int4 — Q5-GGUF won't load — and pays ~2 confounded pt for it).

**⚠ᵉ E4B agentic:** the one clear vLLM regression — E4B agentic is 18 pt *lower* on vLLM
than llama.cpp (not a date-confound; the llama.cpp run is older). E4B's elastic/centroid-head
arch serves knowledge fine on vLLM but its tool-calling degrades. Prefer llama.cpp for E4B agentic.

### Owner test-order campaign (2026-06→07) — the real verdict, incl. vLLM 0.24
The owner asked to eval a set of newer 30–120B chat/coding/orchestrator candidates. First run
on `v0.23.0-aarch64-cu129`; the blocked ones **re-tested on `v0.24.0-aarch64-cu129-ubuntu2404`**.
**ᵛ = the 0.24 image is required.**

| Model | Arch | vLLM 0.23 | vLLM 0.24 |
|---|---|---|---|
| Mistral Medium 3.5 128B | dense (multimodal) | ✅ w/ `--config-format hf --limit-mm-per-prompt {image:0}` but **~3 tok/s** | still ~3 tok/s (dense-bound) |
| Granite 4.1 30B | hybrid Mamba/Transformer | ✅ but **~3.4 tok/s** | **still ~3.4 tok/s** (0.24 doesn't fix the Mamba path) |
| Cohere North-Mini-Code 30B-A3B | MoE | ⛔ `cohere2_moe` loader `KeyError` | ✅ **unblocked, ~27 tok/s** |
| GLM-4.7-Flash 30B-A3B | `Glm4MoeLite` | ⛔ `AssertionError` at init | ✅ **unblocked, ~20 tok/s** |
| Mistral Small 4 119B | MoE (multimodal, NVFP4) | ⛔ NVFP4-MoE `c10::Error` at init | 🟡 **arch fixed** (loads past init) but the 66 GB NVFP4 checkpoint **OOMs during load** on 121 GB UMA — a memory-capacity wall, not arch |
| Mistral Small 3.2 24B | dense (multimodal) | ⛔ tokenizer garble (unsloth HF repo) / no consolidated for mistral-format | not re-run (repo/format issue, not a vLLM-version issue) |

**Bottom line.** Practically usable vLLM models on this GX10 today: the **Gemma + Qwen families**
(0.23/0.24) plus — **on 0.24 only** — **GLM-4.7-Flash** and **Cohere North-Mini-Code** (both fast MoE,
~20–27 tok/s, ~96–97% knowledge). **0.24 is the image to use.** What 0.24 does *not* fix: the
**dense/Mamba speed wall** (Mistral Medium 128B, Granite 4.1 → ~3 tok/s, bandwidth/Mamba-bound) and
the **memory-capacity wall** for the biggest quants (the 119B NVFP4 won't stage into 121 GB UMA).
So: prefer **fast MoE (3–4B active)** for local vLLM on this box; big-dense and hybrid-Mamba are
knowledge-strong but too slow to serve interactively here.

### Provenance notes
- **ᵍ Qwen3.6-35B-A3B** — knowledge 98.65% was measured on the **GX10 vLLM BF16** run (`results/qwen36-35b-a3b-BF16-262k-gx10`, runs 1–5); loop+agentic from the llama.cpp BF16 runs. The **deployed fleet** serves `Q5_K_M stock` on llama.cpp (its own deploy-eval scored ~97.4% knowledge). Treat 98.65% as the model's ceiling, not the exact fleet number.
- **ᶦ Qwen3.5-122B-A10B** — main-table knowledge (98.92%) is the Q5_K_M llama.cpp run; the **vLLM GPTQ-Int4** serving (`results/qwen35-122b-int4-vllm-gx10`, 2026-06-27) is now **judged: 96.60%** (see the vLLM-vs-llama.cpp table below). vLLM serving config: [vLLM cfg](configs/vllm-gx10-serving.md#-qwen35-122b-a10b-moe--gptq-int4-only-on-this-box).
- **ᵖ Gemma 4 31B** — loop is a **partial** run (9 scenarios) from the `q4km` build, not the `q6k` knowledge build. No agentic run exists.
- **ʳ run1 only** — Hermes4-14B (runs 2–3 present but unjudged) and Qwen3.5-35B-A3B (runs 2–5 unjudged).
- **ᑫ Gemma 4 12B** — knowledge/agentic tested at **Q4** on ai-infer3; the linked profile is the `q8-turbo` fleet variant (no Q4 profile exists). 89.9% is the corrected 2-round re-judge (supersedes an earlier inflated 92.4%).
- **ᵛ GLM-4.7-Flash & North-Mini-Code** — 30B-A3B MoE reasoning models, **vLLM-only** (not fleet). Both were **arch-blocked on vLLM 0.23**, unblocked on `v0.24.0-aarch64-cu129-ubuntu2404` — the 0.24 upgrade is what made them runnable on this Blackwell box. Fast (~20 / ~27 tok/s). Agentic is real 30-task tool use; both serve tool-capable (GLM `glm47` on the stock image; Cohere `cohere_command4` needs `cohere_melody` baked into a derived image — see [serving cfg](configs/vllm-gx10-serving.md)). Mid-pack: good mechanics, below the fleet's Qwen3.6-35B (89%).
- **ᶜ North-Mini-Code knowledge** — **93.11% raw**; one of 3 runs lost an entire 40-question chunk to an infinite reasoning-loop (emitted no answers → 0). Loop-excluded ≈ **96.6%**. The loop-spiral tendency (also 2/24 loop gens) is the model's real caveat — guard it with a step/token budget if run unattended.

## Where the detailed config lives
- **llama.cpp fleet models** → `homelab/ansible/inventory/model_profiles/<name>.yml` — authoritative serving config (binary, KV type, slots × ctx, samplers, quant rationale, WHY comments).
- **vLLM / GX10 models** → [`configs/vllm-gx10-serving.md`](configs/vllm-gx10-serving.md) — exact image, parser flags, launch command per model.
- **GX10 GGUF runs** (122B Q5, Nemotron) → the run dir's `KNOWLEDGE-SUMMARY.md` + `run-chunk.sh` (no Ansible profile — playground only).

## How to extract a score yourself
```bash
# Knowledge — sum points across the 9 chunks of run1 (or read KNOWLEDGE-SUMMARY.md when present):
jq -s 'map(to_entries[].value.points)|add as $p|{points:$p,max:(length*2),pct:($p/(length*2)*100)}' \
  results/<dir>/run1/chunk*-ratings.json
# Loop — spiral count:
grep -h is_spiral loop-detection/results/<dir>/*-score.json | grep -c true   # spirals / total files
# Agentic — top-level percentage:
jq '{pct:.percentage, score:"\(.total_score)/\(.max_score)"}' agentic/results/<dir>/agentic-*.json
```

---
*Cross-model verdict docs: [`results/GX10-CAMPAIGN-COMPARISON.md`](results/GX10-CAMPAIGN-COMPARISON.md) (the 4 GX10 models), [`results/gemma4-31b-vs-26b-verdict.md`](results/gemma4-31b-vs-26b-verdict.md), [`results/gemma4-26b-q5-vs-q6-verdict.md`](results/gemma4-26b-q5-vs-q6-verdict.md).*
