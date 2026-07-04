# Mistral Medium 3.5 128B (AWQ-INT4, GX10 vLLM) — Knowledge eval

3-judge (Opus-4.8, 1 pass × 3 runs), 370 questions/run. Served via vLLM
`v0.23.0-aarch64-cu129` AWQ-INT4 (HF config-format, images disabled, mistral tool
parser, ngram spec-decode, 32k ctx). Captured with a relaxed runner (the strict
ID-prefix validator rejects Mistral's looser answer labeling — the Opus judges match
answers to questions by content).

| Run | Pass A | Mean |
|---|---|---|
| run1 | 97.43% | 97.43% |
| run2 | 97.97% | 97.97% |
| run3 | 98.38% | 98.38% |

**Overall: 97.93%** (2174/2220; spread 97.43–98.38, stdev ~0.39)

Per-chunk (mean): chunks 1,2,4,5,6,7,8 = 97–100%; **chunk3 (opentofu/ansible) ~95.9%**
and **chunk9 (scenarios) ~93.3%** the soft spots. Knowledge sits between Gemma 12B
(97.07) and 26B (98.24) — strong, but not a quality leap over the faster MoEs.

## Notes
- AWQ-INT4 is the only weight that fits 121 GB on vLLM (BF16 128B ≈ 256 GB). Quality at
  Int4 is still ~98%, so quantization is not the limiter — **speed is** (~3 tok/s dense).
- No llama.cpp baseline exists for Mistral Medium (not a fleet model) → vLLM-only entry,
  no engine delta.

See VERDICT.md for the loop (2 spirals) + the speed disqualifier for the orchestrator role.
Raw ratings: `run{1,2,3}/chunk{1-9}-ratings-passA.json`.
