# GLM-4.7-Flash 30B-A3B (MoE, reasoning) — vLLM **0.24** GX10 — evaluation

The headline result of the vLLM-0.24 re-test: **GLM-4.7-Flash was fully BLOCKED on vLLM
0.23** (`Glm4MoeLiteForCausalLM` → `AssertionError` at engine init) and is a **strong, fast,
usable model on vLLM 0.24**. Served via `vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404`
BF16, 32k ctx. No llama.cpp baseline (not a fleet model) → vLLM-only.

| Dimension | GLM-4.7-Flash (BF16, vLLM 0.24) | Notes |
|---|---|---|
| Knowledge (~370q, 3-judge Opus-4.8) | **96.80%** (spread 1.62pp) | competitive with the Gemma/Qwen band |
| Loop | **not measured** | the 24-gen run produced only zero-byte responses — withdrawn, see below |
| Speed | **~20 tok/s** | FAST — MoE 3B-active; unlike the dense ~3 tok/s models |
| Agentic (30 tasks, real tool use) | **65.0%** ᵃ (195/300, 27/30 verified) | served with `--tool-call-parser glm47 --reasoning-parser glm47` — tool-calling works |

## Why it matters
This is the proof that **the 0.23 "only Gemma/Qwen" wall was a vLLM-version limit, not a
model limit**. The same GX10, the same Blackwell/sm_121, the same weights — 0.23 refused to
init the engine; 0.24 runs it at 20 tok/s with 96.8% knowledge. A 30B-A3B MoE reasoning model
at 20 tok/s + ~97% knowledge is a genuinely usable local model (coding/agentic candidate — its
intended niche).

## Verdict
**Adopt-worthy on vLLM 0.24.** Fast, strong knowledge, reasoning-capable. Agentic came in at **65%** with real tool use (`glm47` tool-call
parser) — mid-pack: solid tool-calling mechanics, below the fleet's Qwen3.6-35B (89%), so it's a
capable-but-not-leading agentic model. And — critically — 0.24 is now the image to re-test every
other 0.23-blocked model on.

**Serving note:** to use GLM-4.7-Flash as a reasoning+tool model, serve with
`--reasoning-parser glm47 --enable-auto-tool-choice --tool-call-parser glm47` (both `glm47`).

Knowledge detail: `KNOWLEDGE-SUMMARY.md`.

**Loop — withdrawn (2026-07-25).** This verdict previously reported "2 spirals ⚠️" and advised
watching for loop spirals. That was not a measurement: all 24 generations in
`../../loop-detection/results/glm-4.7-flash/` are zero-byte, so the run captured no model output.
The two LD12 entries marked `is_spiral` are scoring artifacts of an empty file missing its
terminal phrase. GLM-4.7-Flash's loop behaviour is simply **unknown** — it has neither been shown
to spiral nor shown to resist. See that directory's `RUN-FAILED.md`; re-running needs the model
re-downloaded (purged from the GX10 at campaign close).

**ᵃ AG27 never reached the model.** It is recorded as `setup_failed` in this run but still contributes 0/10 to the 65.0% total and is counted among the 30 tasks. Excluding it, the score is **67.2% (195/290)**. The raw figure is kept as the headline so it stays comparable with the other 30-task runs.
