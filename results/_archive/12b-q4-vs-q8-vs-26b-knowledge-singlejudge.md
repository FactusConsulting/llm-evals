# Knowledge eval — Q4 vs Q8 vs 26B, one consistent single-judge session (2026-06-09)

**Goal:** a directly comparable knowledge/reasoning number for the three production
models, all generated and judged with the **same method in the same session** —
because the earlier per-model verdicts used different judging setups (the 6-judge
references vs the lenient one-off Q4 run) and were NOT comparable to each other.

## Method (identical for all three)

- **Generation:** the canonical 9-chunk knowledge set (sha-identical across all
  historical runs), 370 scored items / 740 pts. Each chunk sent once via
  `run-chunk-validated.sh` (unique-nonce anti-cache, temp 0.1, top_p 0.95,
  max_tokens 49152) **directly to each host's llama-server** (`:8001`, per-host
  API key) — NOT via LiteLLM — so the quant is guaranteed:
  - Q4  → ai-infer3 `192.168.2.172` (12B **Q4_K**, 6×131k)
  - Q8  → ai-infer2 `192.168.2.171` (12B **Q8_0**, 4×262k) — model file 12.65 GB confirms Q8
  - 26B → ai-infer1 `192.168.2.170` (26B-A4B **Q6_K**, model file 22.85 GB)
- **Judging:** verbatim `judge-knowledge.py` rubric (pass=2 / partial=1 / fail=0),
  one Opus subagent per chunk, **2 independent rounds averaged** per chunk
  (metered ANTHROPIC key is dry → subscription-Opus subagents). Chunk 9 = 10
  scenarios × 3 parts (A reason / B write-runnable-code / C architect), strict on
  Part B (non-runnable stub / fictitious API / invalid syntax = fail).

## Result (2-round average)

| Model | knowledge prose (chunks 1–8) | scenarios (chunk 9) | **TOTAL** | run spread |
| :-- | --: | --: | --: | --: |
| 12B **Q4** (ai3)  | 622.5/680 (91.5%) | 42.5/60 (70.8%) | **665.0/740 = 89.9%** | 654–676 |
| 12B **Q8** (ai2)  | 640.5/680 (94.2%) | 41.0/60 (68.3%) | **681.5/740 = 92.1%** | 681–682 |
| 26B **Q6_K** (ai1)| 647.5/680 (95.2%) | 48.5/60 (80.8%) | **696.0/740 = 94.1%** | 696–696 |

## What this settles

1. **Q4 vs Q8: Q8 is modestly but consistently ahead — ~2 points (89.9 % vs 92.1 %),
   almost entirely in prose knowledge (91.5 % vs 94.2 %).** This *corrects* the earlier
   Q4 verdict of 92.4 %: that number came from a single, more-lenient judging session.
   Re-judged in this consistent session, Q4 lands at 89.9 %. So Q4 does carry a small
   real knowledge penalty vs Q8 — not the "indistinguishable" the lenient run implied,
   but small.
2. **The single-judge method is noisy, and the noise is model-dependent.** On identical
   responses, Q4's two rounds spanned 654–676 (88.4–91.4 %) — a 22-point swing — while
   Q8 (681–682) and 26B (696–696) barely moved. Q4's answers sit in the pass/partial
   gray zone more often, so judges disagree more; Q8/26B answers are more decisively
   correct. The width of Q4's spread is itself a quality signal.
3. **26B leads (94.1 %), and its edge is concentrated in the hardest multi-part
   scenarios** (80.8 % vs ~69–71 % for both 12 Bs) — the bigger model writes more
   genuinely-runnable code for the SC Part-B tasks. On plain prose knowledge the three
   are within ~4 points (91.5 / 94.2 / 95.2 %).

## Caveats / how to read the absolute numbers

- These numbers are **only comparable to each other**, not to the historical 6-judge
  references (31B 98.92 % / 26B 98.56 % / 12B-bf16 97.95 %). This single-judge × 2-round
  method runs ~4–5 points stricter: the SAME 26B scores 94.1 % here vs 98.56 % under the
  6-judge harness. Use the within-session column above for ranking, the references for
  the historical 6-judge scale.
- The most reliable **deterministic** same-harness signal for the Q4-vs-bf16/Q8 question
  remains the **agentic eval** (Q4 65.0 % vs bf16 67.6 % — equivalent within noise,
  0/12 loop-spirals each). For the agentic overflow/failover role ai-infer3 actually
  serves, the ~2-point knowledge gap measured here is immaterial.

## Bottom line

Quality ranking on knowledge is **26B > Q8 > Q4**, gaps ~2 points each, biggest
separation on hard code-writing scenarios. Q4 is a genuine but small step down from Q8
on knowledge prose, and effectively equal on agentic work — fit for its overflow role;
Q8 stays the agentic default; 26B stays the knowledge/planning model. Topology unchanged.
