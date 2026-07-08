# vLLM serving reference — GX10 (DGX Spark, GB10 / sm_121)

Goal: documented, validated vLLM settings per model so each works in **reasoning** mode AND **agentic** (tool-calling) mode. Box: `lars@192.168.2.173`, GB10 compute_cap **12.1 (sm_121)**, 121 GB unified mem, CUDA 13 driver. One model served at a time on `:8000`. This is the GX10 vLLM playground (not in the LiteLLM production fleet — that runs llama.cpp; see `../homelab/ansible/inventory/model_profiles/` for fleet configs).

## Managed serving (2026-07-08) — systemd + vLLM 0.24

The GX10 now runs a **managed, restart-on-boot** vLLM service instead of ad-hoc `docker run`.
Files codified in [`gx10-serving/`](gx10-serving/) (deployed copies live at
`/usr/local/bin/gx10-vllm-serve` and `/etc/systemd/system/vllm-gx10.service` on the box):

- **Image: `vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404`** — 0.24 is required for the
  MoE arches (GLM-4.7-Flash `Glm4MoeLite`, Cohere `cohere2_moe`) that 0.23 refused to init.
- **Swap the served model:** `gx10-vllm-serve <key>` where key ∈ `glm | cohere | gemma-26b | qwen-27b`.
  It rewrites `/etc/gx10-vllm.model`, frees memory (rm + drop_caches + wait — avoids the UMA
  load-OOM race), then starts the container. `systemctl restart vllm-gx10` re-serves the saved key.
- **Default = `glm`** (GLM-4.7-Flash, ~96.8% knowledge, ~20 tok/s). `cohere` = North-Mini-Code
  coding model (~27 tok/s, watch loop-spirals).
- One model at a time (121 GB UMA). The big NVFP4 119B (Mistral Small 4) still OOMs on load
  even on 0.24 — not in the managed set. See `../DASHBOARD.md` for the full campaign verdict.
## Hard-won general rules
- **sm_121 needs a kernel-compatible image.** Plain pip wheels cap at sm_120 → `no kernel image available`. Use vLLM's container images. The standard `v0.23.0-aarch64-cu129` image DOES run on GB10 despite being cu129 (the cu130 requirement was overstated for that tag).
- **vLLM publishes MODEL-SPECIFIC images** (Docker Hub `vllm/vllm-openai`): `qwen3_5-*`, `gemma-*`, `gemma4-unified-*`, `minimax-m3-*`, `glm52-*`, etc. — day-0 builds with that model's arch+parsers. Try these when a model is new/unsupported in mainline.
- **Reasoning + tools fight in old builds.** The reasoning parser swallows everything before `</think>`, so the tool parser never sees tool XML → malformed/dropped tool calls. The **unified Parser.parse() Streaming Parser Engine (vLLM 0.23.0, PR #45413/#44267)** resolves this. Prefer **≥0.23.0**.
- **Field rename in 0.23.0:** chain-of-thought is in `message.reasoning` (NOT `message.reasoning_content`). Update any client that reads `reasoning_content` (LiteLLM, openclaw, llm-evals `run-chunk.sh`).
- Entrypoint: standard `vllm/vllm-openai` images = `[vllm serve]` → pass `<model> <flags>`. NGC `nvcr.io/nvidia/vllm` = `[nvidia_entrypoint.sh]` → pass `vllm serve <model> <flags>`.
- Docker needs `sudo` on the GX10. Memory: `--gpu-memory-utilization 0.85` (unified mem; OS+page-cache share the pool), `--max-num-seqs 4` (bandwidth-bound). `sync; echo 3 > /proc/sys/vm/drop_caches` before launch.

---

## ✅ Qwen3.6-27B (dense, BF16) — validated 2026-06-26
Arch `Qwen3_5ForConditionalGeneration` (`qwen3_5`), multimodal+hybrid. Model: HF safetensors at `/home/lars/models/Qwen3.6-27B-hf` (vLLM can't load GGUF).

| | |
|---|---|
| **Image** | `vllm/vllm-openai:v0.23.0-aarch64-cu129` (runs on sm_121; 0.19.2/0.20.1 = broken parsers) |
| **Reasoning** | `--reasoning-parser qwen3` → CoT in `message.reasoning` |
| **Agentic/tools** | `--enable-auto-tool-choice --tool-call-parser qwen3_xml` → structured `tool_calls` w/ params (AG1 10/10) |
| **Perf** | `--speculative-config '{"method":"ngram","num_speculative_tokens":4,"prompt_lookup_min":2,"prompt_lookup_max":5}'` (~2.2× on repetitive); dense BF16 ~4.5–5 tok/s baseline (bandwidth wall) |

```
sudo docker run -d --name vllm --ipc=host --gpus all --restart unless-stopped \
  -p 8000:8000 -v /home/lars/models/Qwen3.6-27B-hf:/model:ro -e HF_HUB_OFFLINE=1 \
  -e OTEL_SERVICE_NAME=vllm-gx10 \
  vllm/vllm-openai:v0.23.0-aarch64-cu129 \
  /model --served-model-name qwen3.6-27b --dtype bfloat16 \
  --gpu-memory-utilization 0.85 --max-model-len 131072 --max-num-seqs 4 \
  --reasoning-parser qwen3 --enable-prefix-caching --trust-remote-code \
  --enable-auto-tool-choice --tool-call-parser qwen3_xml \
  --speculative-config '{"method":"ngram","num_speculative_tokens":4,"prompt_lookup_min":2,"prompt_lookup_max":5}' \
  --otlp-traces-endpoint http://192.168.2.58:4317
```
**Caveats:** multi-function-in-one-`<tool_call>` still broken upstream (#43713) — single-function unaffected. `reasoning` field rename.

---

## ✅ Gemma 4 family (12B validated; one config for all 4 sizes) — validated 2026-06-26
Arch `Gemma4UnifiedForConditionalGeneration` (12B) / `Gemma4ForConditionalGeneration` (E4B/26B-A4B/31B). HF safetensors `google/gemma-4-<size>-it` (NOT gated). All prior homelab Gemma evals used `-it` (instruct), verified.

| | |
|---|---|
| **Image** | `vllm/vllm-openai:v0.23.0-aarch64-cu129` (Gemma4 arch supported; no separate image needed) |
| **Reasoning** | `--reasoning-parser gemma4` → CoT in `message.reasoning`. Gemma uses a CHANNEL format (`<|channel>thought…<channel|>`, harmony-style), NOT `<think>` tags. Trigger via `chat_template_kwargs:{enable_thinking:true}` (auto-on with tools/system prompt). |
| **Agentic/tools** | `--enable-auto-tool-choice --tool-call-parser gemma4` → structured tool_calls w/ params |
| **Weights** | BF16 (≥Q8). 121GB UMA fits BF16 even for 31B (~62GB). |
| **Perf** | BF16 + ngram spec-decode + f16 KV. ngram ~2.4× on repetitive/code (7.4→17.8 tok/s). **MTP blocked** by the ≥Q8 floor (-it weights have no MTP heads). **KV fp8 not needed** on 121GB UMA — keep f16 KV. |

```
sudo docker run -d --name vllm --ipc=host --gpus all --restart unless-stopped \
  -p 8000:8000 -v /home/lars/models/gemma-4-12B-it:/model:ro -e HF_HUB_OFFLINE=1 \
  -e OTEL_SERVICE_NAME=vllm-gx10 \
  vllm/vllm-openai:v0.23.0-aarch64-cu129 \
  /model --served-model-name gemma4-12b --dtype bfloat16 \
  --gpu-memory-utilization 0.85 --max-model-len 131072 --max-num-seqs 4 \
  --reasoning-parser gemma4 --enable-auto-tool-choice --tool-call-parser gemma4 \
  --enable-prefix-caching --trust-remote-code \
  --speculative-config '{"method":"ngram","num_speculative_tokens":4,"prompt_lookup_min":2,"prompt_lookup_max":5}' \
  --otlp-traces-endpoint http://192.168.2.58:4317
```
Per-size (same config + own model dir): **E4B** ~19.8 tok/s; **26B-A4B** ~14.3 tok/s (thinking verbose → give generous `max_tokens`); **31B** ~3.9 tok/s (dense, bandwidth-bound). All: reasoning separated + tools verified.

---

## 🟡 Qwen3.5-122B-A10B (MoE) — GPTQ-Int4 only on this box
**HARD FINDINGS (2026-06-27):**
- **≥Q8 does NOT fit the GX10.** FP8 ≈ ~122GB > 121GB unified mem → won't load even alone. The ≥Q8 preference is unmeetable for the 122B on this box.
- **Q5_K_M GGUF (~91GB, fits) is BLOCKED on vLLM.** `ValueError: GGUF model with architecture qwen35moe is not supported yet`. Root cause: `qwen35moe` is NOT in transformers' GGUF registry (`integrations/ggml.py` has qwen2/qwen2_moe/qwen3/qwen3_moe, NOT qwen35moe), not even on `main`; vLLM inherits the gap. **qwen35moe GGUF = llama.cpp-only.**
- **On vLLM the 122B can only run as Int4 safetensors** (`Qwen/Qwen3.5-122B-A10B-GPTQ-Int4`, ~61GB — fits, loads, runs on sm_121). Launch = the Qwen pattern but `--served-model-name qwen35-122b --gpu-memory-utilization 0.92 --max-model-len 32768 --max-num-seqs 2`, no `--dtype`, no spec-decode (quant auto-detected). KV `auto` (=f16), 36.4 GiB, ~1.3M tokens, ~40× concurrency at 32768.

## ⬜ Gemma diffusion (`google/diffusiongemma-26B-A4B-it`) — TODO (expected vLLM LIMIT)
Text-diffusion model (iterative denoising, NOT autoregressive). vLLM's engine (PagedAttention, continuous batching, AR decode) does not serve diffusion LLMs. EXPECT vLLM to reject the arch. This is the deliberate "what vLLM can't do" data point — confirm the failure mode, then note it needs a diffusion-specific runtime. Don't force it.
