# Cohere North-Mini-Code 1.0 30B-A3B (MoE coding) — vLLM 0.24 — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. Served via
`vllm/vllm-openai:v0.24.0-aarch64-cu129-ubuntu2404` BF16, 32k ctx. **Blocked on 0.23**
(`cohere2_moe` loader KeyError); works on 0.24.

| Run | Pass A | Mean | Note |
|---|---|---|---|
| run1 | 96.49% | 96.49% | normal |
| run2 | 86.49% | 86.49% | **chunk3 = 0** (infinite reasoning loop on T18, no answers emitted) |
| run3 | 96.35% | 96.35% | normal |

**Overall (raw): 93.11%** (2067/2220) · **loop-excluded ≈ 96.6%** (drop run2's zeroed chunk3)

The chunk3-run2 zero is a **stochastic reasoning-loop**, not a knowledge gap (run1/run3
chunk3 = 93.8/92.5%). Per-chunk otherwise: .NET/Py ~99, arch 100, Go/Rust ~95, JS/Bash/PS ~95,
Tofu/Ansible ~93, scenarios ~94. Coding-strong.

## Notes
- **~26.7 tok/s** (MoE 3B-active) — fast. Loop-spiral tendency (2/24 loop gens + the run2 chunk
  loss) is the real caveat — see VERDICT.md.
- No llama.cpp baseline → vLLM-only. Story = the **0.23→0.24 unblock**.

Raw ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
