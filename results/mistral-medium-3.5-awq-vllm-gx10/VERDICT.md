# Mistral Medium 3.5 128B (dense, AWQ-INT4, vLLM GX10) — evaluation

Owner's test-order #1: intended as the primary chat / architecture / refactoring /
agent-orchestrator model ("most likely to give something other than Qwen/Gemma/Nemotron").
Served via vLLM `v0.23.0-aarch64-cu129`, `cyankiwi/...-AWQ-INT4`, **HF config-format +
`--limit-mm-per-prompt {image:0}`** (the model is multimodal/Pixtral — the default
mistral-format path crashes the `MistralCommonPixtralProcessor` at init; HF format +
no-image dodges it), `--tool-call-parser mistral`, 32k ctx, ngram spec-decode.

| Dimension | Mistral Medium 3.5 (AWQ-INT4) | Notes |
|---|---|---|
| Knowledge (~370q, 3-judge Opus-4.8) | **97.93%** (spread 0.95pp) | strong — between Gemma 12B (97.07) and 26B (98.24) |
| Loop (24 gens) | **2 spirals** ⚠️ | the FIRST model in the campaign with spirals (Gemma family all 0) |
| Agentic | **not run** | ~3 tok/s would make the 30-task harness 6–10 h; the speed already disqualifies the role |

## The headline: too slow for its intended role
Dense 128B at **AWQ-INT4 runs ~3 tok/s** on the GX10 (even with ngram spec-decode) —
bandwidth-bound like every dense >30B here, but 128B is the worst. The knowledge-eval
gen needed re-runs because the bigger chunks blew a 30-min per-request timeout. A model
that emits ~3 tokens/sec is **not viable as a responsive primary chat / orchestrator**
model, which is exactly the role it was wanted for. It is also Int4 (the only weight that
fits 121 GB on vLLM — like the Qwen 122B), so this is its best-case speed here.

## Verdict
Knowledge is genuinely strong (~98%, competitive with the Gemma family) and it IS a
different model family — but it does **not clearly beat** the much faster MoE options
(Qwen3.6-35B, Gemma 26B-A4B) on quality, shows **2 loop spirals** where they show none,
and is **~10–30× slower** than the MoEs. For the primary-orchestrator use case the owner
had in mind, the ~3 tok/s speed rules it out. Keep as a knowledge reference / occasional
"second opinion" model; do not adopt as the interactive default. Agentic left unrun by
design (speed).

Knowledge detail: `KNOWLEDGE-SUMMARY.md`. Loop: `../../loop-detection/results/mistral-medium-3.5/` (24 gens, 2 spirals).
