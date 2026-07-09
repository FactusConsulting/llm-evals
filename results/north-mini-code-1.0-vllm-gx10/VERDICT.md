# Cohere North-Mini-Code 1.0 30B-A3B (MoE coding) — vLLM **0.24** GX10 — evaluation

Owner's test-order #2: wanted as a **pure coding-agent / subagent** (OpenCode/Aider/SWE-agent
flows; Go, Rust, C#, PowerShell, k8s YAML, Helm, OpenTofu). **Blocked on vLLM 0.23**
(`cohere2_moe.py` loader `KeyError: layers.0.mlp.down_proj.weight`) → **works on vLLM 0.24**.
Served via `vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404` BF16, 32k ctx. No llama.cpp
baseline → vLLM-only.

| Dimension | North-Mini-Code (BF16, vLLM 0.24) | Notes |
|---|---|---|
| Knowledge (~370q, 3-judge Opus-4.8) | **93.11% raw** / **~96.6% loop-excluded** | one run lost chunk3 entirely to a reasoning loop (see below) |
| Loop (24 gens) | **2 spirals** ⚠️ | + a knowledge-eval chunk was zeroed by an infinite reasoning loop (T18) |
| Speed | **~26.7 tok/s** | fast — MoE 3B-active |
| Agentic (30 tasks, real tool use) | **70.0%** (210/300, 23/30 verified) | 23 PASS / 7 FAIL — see serving note below |

## Coding chunks (the owner's languages)
Strong where it matters: **.NET/Python ~99%**, **Go/Rust ~95%**, **JS/Bash/PowerShell ~95%**,
**OpenTofu/Ansible ~93%** (when it doesn't loop). Architecture/on-prem chunks a clean 100%.

## The caveat: reasoning-loop spirals
North-Mini-Code is a reasoning model and **spirals into infinite reasoning** on a non-trivial
fraction of prompts: 2/24 loop-detection gens flagged, and **1 of 3 knowledge runs lost an
entire 40-question chunk** (chunk3, stuck on one question, emitted no final answers → 0). For a
model meant to run **unattended as a coding subagent**, that's a real reliability risk — a
spiral burns tokens/time and produces nothing. Interactive use is fine (you see it and stop it).

## Verdict
**Unblocked by 0.24 and genuinely strong + fast at coding** — a legitimate local coding model.
BUT the loop-spiral tendency means: use it interactively / with a hard step+token budget and a
loop-detector in the agent harness; do **not** turn it loose fully unattended without those
guards. Agentic came in at **70.0%** (210/300, 23/30 verified) under real tool use — the highest
of the two GX10 0.24 MoE models (GLM-4.7-Flash 65%), consistent with its coding-agent niche,
though still below the fleet's Qwen3.6-35B (89%).

## Serving note (tool-calling requires an extra package)
Cohere's tool-call parsers (`cohere_command3` / `cohere_command4`) are **not usable in the stock
`vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404` image** — they lazy-import the `cohere_melody`
package, which isn't installed → `--enable-auto-tool-choice` crashes engine init with
`tool_parser:'cohere_command4' which has not been registered`. Fix: bake `cohere_melody` (has a
`cp312 manylinux aarch64` wheel) into a derived image and serve from it:

```dockerfile
FROM vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404
RUN pip install --no-cache-dir cohere_melody
```
→ `vllm-gx10:0.24-cohere`, then serve with
`--reasoning-parser cohere_command4 --enable-auto-tool-choice --tool-call-parser cohere_command4`.
(GLM-4.7-Flash's `glm47` parser needs no extra package — it works on the stock image.)

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Loop: `../../loop-detection/results/north-mini-code/` (24 gens, 2 spirals).
