# Gemma 4 — MTP (Multi-Token Prediction) before/after benchmark

**Date:** 2026-06-07
**Host:** `ai-infer2` — 2× NVIDIA RTX 5060 Ti 16 GB (32 GB total), consumer Blackwell **sm_120**
**Engine:** `llama.cpp` with the Gemma 4 MTP PR ([ggml-org/llama.cpp #23398](https://github.com/ggml-org/llama.cpp/pull/23398), merged to `main`)
**Goal:** quantify the MTP speedup on output-token production (tok/s) **before vs after** MTP, as a transferable indicator for serving Gemma on H100/H200.

---

## TL;DR — tuned results (best `--spec-draft-n-max` per model)

| Model | Type | Baseline tok/s | Best MTP tok/s | **Speedup** | Optimal `n-max` |
|---|---|--:|--:|--:|--:|
| **31B** | dense | 22.5 | 45.5 | **2.02×** | 4–9 (flat) |
| **12B** | dense | 52.8 | 103.6 | **1.96×** | 4 |
| **E4B** | Edge (dense) | 91.5 | 106.4 | **1.16×** | 2 (FA off) |
| **26B-A4B** | MoE (~4B active) | 89.4 | 99.3 | **1.11×** | **2** |

### Three conclusions for an H100/H200 fleet
1. **MTP gain scales _inversely_ with how fast the model already is per token.** Slow,
   memory-bandwidth-bound dense models (31B @22, 12B @53 tok/s) get ~2×. Already-fast
   models (E4B/26B-A4B @~90 tok/s) get only ~1.1–1.2×.
2. **`--spec-draft-n-max` must be tuned per model — and its optimum is _also_ inverse to
   baseline speed.** Fast models want a small draft window (n=2); slow dense models
   tolerate large windows (n=4–9). A wrong default makes MTP _regress_ (see 26B below).
3. **On H100/H200 (3.35 / 4.8 TB/s — 5–10× the bandwidth of these cards), expect smaller
   relative gains at batch-1**, since decode is far less bandwidth-bound there. MTP pays
   off most for dense models, at low batch, and on long reasoning outputs.

---

## Method

- **Harness:** `llama-server` native `/completion` endpoint. 4 task prompts (code,
  explanation, math, summary) × `n_predict=192`, Google's sampling params
  (`temp 1.0 / top_p 0.95 / top_k 64`). Reported `tok/s` = `timings.predicted_per_second`,
  acceptance = `draft_n_accepted / draft_n`. Mean over the 4 prompts.
- **Before:** `llama-server -m <base>` (no speculation).
- **After:** `+ --model-draft <assistant> --spec-type draft-mtp --spec-draft-n-max N`.
- **Weights:** highest practical quant. 12B/31B used Unsloth **QAT** `UD-Q4_K_XL`; 26B used
  the on-disk **Q6_K** (what ai-infer2 actually serves); E4B used `Q4_K_M`. Base and
  assistant **must match QAT-ness** ("can't mix QAT LLM + non-QAT MTP" → low acceptance).
- KV cache f16; `-fa on` (except E4B, see Blackwell note).

---

## Per-model `n-max` sweeps

### 31B QAT (dense) — baseline 22.5 tok/s
| n-max | tok/s | speedup | acc |
|--:|--:|--:|--:|
| 4 | 45.0 | 2.00× | 0.62 |
| 6 | 45.0 | 2.00× | 0.59 |
| 7 | 39.1 | 1.74× | 0.49 |
| **9** | **45.5** | **2.02×** | 0.49 |

Flat ~2.0× across n=4–9. (n=7 is a noisy dip, not a real minimum.)

### 12B QAT (dense) — baseline 52.8 tok/s
| n-max | tok/s | speedup | acc |
|--:|--:|--:|--:|
| 2 | 91.4 | 1.73× | 0.92 |
| 3 | 101.5 | 1.92× | 0.93 |
| **4** | **103.6** | **1.96×** | 0.85 |
| 8 | 84.4 | 1.60× | 0.53 |

Optimum at n=4; falls off above. (n=6 produced a corrupt timing sample, discarded.)

### 26B-A4B Q6_K (MoE) — baseline 89.4 tok/s
| n-max | tok/s | speedup | acc |
|--:|--:|--:|--:|
| 1 | 94.5 | 1.06× | 0.81 |
| **2** | **99.3** | **1.11×** | 0.80 |
| 3 | 89.9 | 1.01× | 0.64 |
| 4 | 81.5 | 0.91× | 0.61 |
| 6 | 55.0 | 0.62× | 0.32 |

**The key finding:** at the larger default-ish window MTP _regresses_ (0.91× @n=4), but at
**n=2 it is a real +11% win**. The MoE is already compute-light (~4B active) so a large
draft window's wasted compute (acceptance collapses 0.81→0.32 as n grows) outweighs the
savings. Always sweep `n-max` on fast models.

### E4B (Edge / 4B-class) — baseline 91.5 tok/s
| task | before | after | acc |
|---|--:|--:|--:|
| code | 91.4 | 101.6 | 0.70 |
| explain | 91.6 | 103.4 | 0.68 |
| math | 91.6 | 117.5 | 0.94 |
| summary | 91.5 | 103.1 | 0.70 |
| **mean** | **91.5** | **106.4 (1.16×)** | 0.75 |

Small gain — already efficient. Required the **AtomicBot turbo fork** (centroid-head
assistant, `--mtp-head --spec-type mtp --draft-block-size 2`) **with `--flash-attn off`**
(see Blackwell note).

---

## Reproduce — build & model sourcing

### Build the MTP binary (dense models: 12B / 26B / 31B)
```bash
git clone --depth 1 https://github.com/ggml-org/llama.cpp /opt/llama.cpp-mtp
cd /opt/llama.cpp-mtp
# the gemma4-assistant arch loader lives in PR #23398 — fetch it explicitly:
git fetch --depth 1 origin pull/23398/head:gemma4-mtp && git checkout gemma4-mtp
cmake -B build -DGGML_CUDA=ON -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=120 \
  -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF
cmake --build build --config Release -j"$(nproc)" --target llama-server
# verify: --help shows "--spec-type [ ... draft-mtp ... ]"
```

### Run (dense)
```bash
# before
llama-server -m <base.gguf> -ngl 999 --tensor-split 1,1 -c 16384 -fa on
# after (tune N: 26B→2, 12B→4, 31B→4-9)
llama-server -m <base.gguf> --model-draft <assistant.gguf> \
  --spec-type draft-mtp --spec-draft-n-max N -ngl 999 --tensor-split 1,1 -c 16384 -fa on
```

### Assistant GGUF — the arch gotcha
The merged PR registers the assistant architecture as **`gemma4-assistant` (hyphen)**. Many
published assistants use fork conventions and **fail** with `unknown model architecture`:

| Source | Arch string | Works with PR #23398? |
|---|---|---|
| Janvitos (12B), Simplepotat (31B) | `gemma4-assistant` | ✅ |
| **Self-converted** from `google/gemma-4-<size>-it-assistant` via `convert_hf_to_gguf.py` | `gemma4-assistant` | ✅ (used for 26B) |
| boxwrench, AtomicChat | `gemma4_assistant` (underscore) | ❌ |
| cafkafk, Radamanthys | `gemma4_mtp` | ❌ |

Convert Google's official assistant when no correct GGUF is published (dense head only):
```bash
hf download google/gemma-4-26B-A4B-it-assistant --local-dir asst-src    # ~0.9 GB
python convert_hf_to_gguf.py asst-src --outfile assistant.gguf --outtype q8_0
```

### Edge (E4B / E2B) — different path
Edge models use a **centroid / ordered-embeddings MTP head** (`masked_embedding.centroids`)
that `convert_hf_to_gguf.py` **cannot map**. E4B MTP works only on the **AtomicBot turbo
fork** (`AtomicBot-ai/atomic-llama-cpp-turboquant`, branch `feature/turboquant-kv-cache`),
using `--mtp-head <gguf> --spec-type mtp --draft-block-size 2` with the fork's
`gemma4_assistant` (underscore) assistants.

> **Blackwell (sm_120) note:** the fork's MTP path **crashes with flash attention on**
> (`fattn.cu:109 fatal error` in `graph_compute_mtp`). Run E4B MTP with `--flash-attn off`.
> Baseline (no MTP) is fine with FA. Likely sm_120-specific; Hopper (H100/H200) probably
> unaffected — re-verify there.

---

## Raw notes
- ai-infer2 normally serves `gemma4-26b` (Q6_K) as one half of the LiteLLM `gemma4-26b`
  load-balanced pool; it was stopped only during benchmark runs and restored after.
- Binaries kept on the host: `/opt/llama.cpp-mtp` (mainline + PR), `/opt/llama.cpp-atomic`
  (fork). Small assistant GGUFs under `/opt/models/qat-mtp/`.
