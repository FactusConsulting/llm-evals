# Verdict — GLM-5.3-Flash UD-Q4_K_XL across both GB10 boxes over ggml RPC

**Date**: 2026-10-24
**Hosts**: gx10-59c7 (head, llama-server) + gx10-1dd1 (worker, ggml-rpc-server), DGX Spark / GB10, 121 GiB unified each, direct 200G cable (RDMA)
**Endpoint**: `https://gx10-59c7.lwa.dk` (fleet key), alias `glm5.3-flash`, router role `bigbrain`

## Setup under test

| | |
|---|---|
| build_info | `b11036-86ebfef2c` (GLM-5.3 PR pin, `-DGGML_RPC=ON` on both boxes) |
| chat template sha256 | `d332fd5766d800fb` — identical to the Q2 run |
| model | `GLM-5.3-Flash-GGUF/UD-Q4_K_XL` @ `2975ab41`, 6 shards, 199 GB on disk |
| placement | `--rpc 10.200.0.2:50052 --device CUDA0,RPC0`, default tensor split |
| context | 262144 total / 1 slot = **262144 per slot** |
| KV cache | `q8_0` |
| speculative decoding | `--spec-type draft-mtp --spec-draft-n-max 2`, no draft model |
| memory | head 114 of 121 GiB used (7 GiB free), worker 112 of 121 (9 GiB free), model resident |
| sampling | temperature 0.1, top_p 0.95, max_tokens 49152 (knowledge) |
| homelab | profile `glm5.3-flash-q4kxl-mtp-rpc-gb10`, deployed by `playbooks/llm/llama_cpp_rpc.yaml` (#1074) |

## TL;DR

Q4 over two boxes scores the same as Q2 on one — **98.38 %** against the Q2 three-run
mean of 98.69 %, a −0.31 pp gap inside the single-run noise band — with the same two
failure modes (one-line HCL compression, wrong exact identifiers) and the same perfect
analysis/architecture parts. What the second box buys is not accuracy on this suite but
**one 262k slot, q8_0 KV and a Q4 quant at once**, at the price of a slower decode
(13–15 tok/s against Q2's ~22) and the worker's GPU.

## Score

| Suite | Result |
|---|---|
| Knowledge (370 q, two judges, mean(A,B)) | **728/740 = 98.38 %**, 358 pass / 12 partial / 0 fail, agreement 99.2 %, alt_acceptable 15.1 % |
| Chunk 9 Part A / B / C | 100 / **75.0** / 100 % |
| Loop detection (12 scenarios, 1 pass, reasoning budget 16384) | 10 clean, LD11 false positive, **LD2 empty (600 s cap)** |
| ds4-eval core, seed 1 (external, stopped at 28/92) | 27/27 correct in 103 min |

Per-chunk and per-question detail: `judge-summary.md`, `run1/judge.json`.

## What the quant costs — and does not

Nothing measurable on the knowledge suite. The twelve partials are the Q2 verdict's
list with the same names on it: SC4-B and SC9-B compress HCL blocks onto one line with
commas; A19 ends a Jinja line with `{% endif %}` and lets `trim_blocks` eat the newline;
A20 invents `community.aws.elb_application_lb_target`; PS14/PS19 state PowerShell
limits that do not exist. The quant changes none of it. The suite is saturated at this
level (README) and only confirms the build is sound.

## Throughput

Measured on this deployment on 2026-10-24, one request at a time:

| Prompt | Prefill | Decode |
|---|---|---|
| short | — | 15.3 tok/s |
| 14k | 300 tok/s | 13.5 tok/s |
| 57k | 247 tok/s | 13.1 tok/s |
| 115k | 186 tok/s | 11.6 tok/s |

MTP acceptance 0.69. The knowledge run took 180 min for 9 chunks (11–41 min each);
the loop pass 43 min. Against Q2 on one box (~22 tok/s), the RPC hop and the larger
weights cost roughly a third of the decode rate; ds4 core's first 27 cases took 103 min
here against 83 min on Q2.

## Loop detection

12 scenarios, one pass, `--reasoning-budget 16384`, `curl --max-time 600`.

| | |
|---|---|
| Clean | 10 of 12 |
| LD11 | `REPEATED_PARAGRAPH` — the known false positive: the cumulative table the scenario demands repeats its rows by design |
| LD2 | `EMPTY_RESPONSE` — curl's 600 s cap hit before the answer; at 13 tok/s the cap holds ~8k tokens, and a 16384 reasoning budget can spend all of that |
| Word counts | 151–671 (no scenario ran long) |

No reasoning spirals, no task-expansion creep; it stops cleanly on LD4, LD9 and LD10.
LD2 is the one real mark, and it is a speed mark, not a stopping mark: the same cap gave
dsv41 four empties and the Q2 campaign pass two. Comparing loop passes across models of
different speed on this runner compares their decode rate as much as their behaviour.

## Run conditions — read this before comparing

- One run, not three. The Q2 baseline has three; the method's noise floor for a single
  run is ~1 pp, and the gap here is 0.31 pp.
- Judged by two Claude Code Opus subagents with the `judge-llm-eval/2.0` rubric; this
  pair set `alternative_acceptable` on 15 % of questions against ~30 % for the Q2
  judges, so if anything they read the key more literally.
- Nothing else used the head during the run (one slot; bigbrain traffic would have
  queued behind it).
- Agentic and narrow-delivery were not run: their runners hardcode 4096 tokens / 120 s
  and 600 s with no reasoning budget, which at 13 tok/s with thinking on measures the
  timeout, not the model.

## Decision

Keep both boxes on `glm5.3-flash-q4kxl-mtp-rpc-gb10`. The score says the build is as
good as Q2; the reason to run it is the slot — a single 262k context with q8_0 KV for
hour-long agentic work — and the memory headroom (7 + 9 GiB) says 512k is the next thing
to try with `llama_cpp_tensor_split` toward the worker; 1M needs a smaller quant.

What this run does not settle: whether Q4 beats Q2 on the external ranking suites. ds4
core stopped at 27/27 (Q2: 27/27 on the same cases); hard, BFCL and tau2 were not run.
