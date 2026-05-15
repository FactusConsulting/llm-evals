# Verdict — Gemma 4 31B Q6_K + turbo4 (single-slot 128k) — JUDGING BLOCKED

**Date**: 2026-05-15
**Host**: ai-infer2 (192.168.2.171), 2×16 GB RTX 5060 Ti
**Status**: ⚠️ Full eval RUN complete and clean; **LLM-judge scoring blocked on Anthropic billing**. No scored % yet.

## Setup under test

- Model: `bartowski/google_gemma-4-31B-it-GGUF` **Q6_K** (dense 31B), ~25.5 GB
- llama.cpp **turbo** fork, **turbo4 KV** (`TURBO_LAYER_ADAPTIVE=2`), single slot, **131072 ctx (128k)**
- interleaved jinja + `enable_thinking: true`, vision off
- Endpoint `http://192.168.2.171:8001/v1/chat/completions`, alias `gemma4-31b`
- Profile: `ansible/inventory/model_profiles/gemma4-31b-q6k-turbo.yml` (homelab PR #349, merged)
- Highest weight resolution that fits 32 GB (Q8_0 overflows; 147k/163k ctx OOM — see profile header)

## What completed

The **full suite ran clean**: 5 runs × 9 chunks = **45/45 chunk responses**, 0 ERROR,
0 truncated (<2 KB), substantive output (per-chunk run-mean 11.5–18.7 KB). Raw responses
preserved under `run{1..5}/chunk{1..9}-response.txt` and committed — the judge can be
re-run against them later with zero loss.

## Why there is no score

`judge-knowledge.py` scores every answer with Claude Opus via the Anthropic API. Every
call returned **HTTP 400** with:

> `invalid_request_error: Your credit balance is too low to access the Anthropic API.`

Confirmed independently against both `claude-opus-4-6` and `claude-opus-4-7` with the
same key (the one in `ansible/playbooks/openclaw/group_vars/openclaw/vault.yml`
`vault_anthropic_api_key`) — identical credit-balance error, so this is an account
billing state, not a model-ID or request-schema problem. The ~3700 garbage
`*-ratings.json` the failed run wrote were deleted; only valid run data remains.

## To complete this verdict (no re-run of the model needed)

1. Fund the Anthropic account behind `vault_anthropic_api_key` (or supply a funded key
   via `ANTHROPIC_API_KEY`).
2. Re-judge the already-captured responses:
   ```
   cd ~/source/llm-evals
   ANTHROPIC_API_KEY=<funded key> python3 judge-knowledge.py \
     --model-dir results/gemma4-31b-q6k-turbo-128k-ai-infer2 \
     --runs 1 2 3 4 5 --chunks 1 2 3 4 5 6 7 8 9
   ```
3. Compare the resulting mean % against the current baseline
   **`gemma4-26b-q6k-458k-turbo4-v2-ai-infer2` = 98.56%** (3-run mean). The 2026-04-14
   eval already rejected 31B for the *2-slot agentic* role on quality grounds; this
   single-slot max-context revisit needs its own number before any production decision.

## Side note (also possibly billing-related)

If the openclaw fleet uses this same Anthropic key as a fallback provider, an empty
credit balance there is worth checking separately — though our agents run primarily on
the local Gemma/Hermes endpoints, so impact is likely limited to explicit
Anthropic-routed turns.
