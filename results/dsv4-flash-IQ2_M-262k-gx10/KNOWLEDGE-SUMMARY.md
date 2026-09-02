# DeepSeek-V4-Flash-0731 UD-IQ2_M (GX10) — Knowledge eval

6-judge (Opus, 2/run × 3 runs), 370 questions/run. llama.cpp master, :30000,
alias dsv4-flash, 262144 ctx, KV q8_0, temp 0.1, max_tokens 49152 (thinking
counts against it), curl-timeout 3600s.

| Run | Judge A | Judge B | Mean |
|---|---|---|---|
| run1 | 96.2% | 96.6% | 96.42% |
| run2 | 97.2% | 97.0% | 97.09% |
| run3 | 95.9% | 95.8% | 95.88% |

**Overall: 96.46%** (spread 95.8–97.2, stdev 0.56; inter-rater agreement 97.6–98.6%/run)

TPS (samme 256-token completion-prompt, cache_prompt=false):
**17.6 tok/s** generation / 85.7 prefill. (IQ3_XXS på samme boks: 16.8 gen / 42.5 prefill.)

Reference: Qwen3.6-35B-A3B BF16 = 98.65%, Q5-fleet = 97.4% (samme eval, samme metode).

**Konsistent fejl på tværs af alle 3 runs:** SC9-B (AWS WAFv2 i Terraform) — begge
dommere fail i alle runs: opfundne provider-attributter + omvendt geo-blocking-logik.
SC4-B er fail/partial-grænsetilfælde i alle 3 runs. Klassisk lav-kvant-symptom:
fiktive API-overflader på snævre schema-domæner.

Verdict: **statistisk ens med IQ3_XXS (96.67%)** — Δ 0.21 pp er inde i støjen.
Se `../dsv4-flash-IQ3_XXS-262k-gx10/KNOWLEDGE-SUMMARY.md` for det fulde Q2-vs-Q3-facit
(Q2 vinder på fart + draft-plads).
Run1 kørte delvist før strømafbrydelsen 2026-08-07 (chunk3 re-kørt med hævet timeout);
run2 chunk1 ligeledes fra før afbrydelsen — server og flag identiske på tværs.
