# IBM Granite 4.1 30B (hybrid Mamba/Transformer, GX10 vLLM) — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. vLLM `v0.23.0-aarch64-cu129`
BF16, 131k ctx, ngram spec-decode. Captured with the relaxed runner (Granite labels
loosely on some chunks; Opus judges match by content).

| Run | Pass A | Mean |
|---|---|---|
| run1 | 96.76% | 96.76% |
| run2 | 96.62% | 96.62% |
| run3 | 95.81% | 95.81% |

**Overall: 96.40%** (2140/2220; spread 95.81–96.76, stdev ~0.42)

Per-chunk (mean): chunk7 (arch) 100%, chunks 1/4/5/8 = 97–100%, chunk6 ~95%,
chunks 2/3 ~94–96%; **chunk9 (scenarios) ~84.4%** the weak spot. Knowledge sits in the
Gemma-E4B/12B band — solid for an enterprise-tuned model.

## Notes
- **~3 tok/s** on vLLM 0.23/Blackwell (hybrid Mamba-2 layers unoptimized) — the practical
  blocker; see VERDICT.md. Agentic left unrun (speed).
- No llama.cpp baseline (not a fleet model) → vLLM-only, no engine delta.

Raw ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
