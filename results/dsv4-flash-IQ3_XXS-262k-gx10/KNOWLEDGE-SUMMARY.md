# DeepSeek-V4-Flash-0731 UD-IQ3_XXS (GX10) — Knowledge eval

6-judge (Opus, 2/run × 3 runs), 370 questions/run. Samme server-setup som IQ2_M
(llama.cpp master, :30000, alias dsv4-flash, 262144 ctx, KV q8_0, temp 0.1).

| Run | Judge A | Judge B | Mean |
|---|---|---|---|
| run1 | 97.0% | 96.9% | 96.96% |
| run2 | 96.2% | 95.8% | 96.01% |
| run3 | 96.9% | 97.2% | 97.03% |

**Overall: 96.67%** (spread 95.8–97.2, stdev 0.53; enighed 97.0–97.8%/run)

TPS (samme 256-token completion, cache_prompt=false): **16.8 tok/s** gen / 42.5 prefill.

## Q2 vs Q3 — facit

| | UD-IQ2_M | UD-IQ3_XXS | Δ |
|---|---|---|---|
| Knowledge | 96.46% | **96.67%** | +0.21 pp — **inde i støjen** (run-spread ±0.6) |
| TPS gen | **17.6** | 16.8 | −5% |
| TPS prefill | **85.7** | 42.5 | −50% |
| Størrelse | **90.9 GB** | 104.2 GB | +13.3 GB |
| + dspark-draft (10.9 GB) | **101.8 GB ✓ passer** | 115.1 GB ✘ | draft kun mulig på Q2 |

Kvalitativt: hver kvant har sit eget konsistente svage punkt (IQ2: SC9-B/WAFv2-schema
i alle 3 runs; IQ3: SC3-B i 2 af 3) — intet systematisk Q2-degraderingsmønster.

**Verdict: Q3 giver ingen målbar knowledge-gevinst over Q2 på denne model.**
Q2 er hurtigere (især prefill — mærkbart på pi'ens 16k-systemprompt), og frigør
~13 GB der muliggør dspark-draften + fuld 262k ctx samtidig — kombinationen
Q3+draft+262k var fysisk umulig på 121 GB.

Drift-note (run2/chunk3): IQ3 brændte 3× hele 49152-token-budgettet på reasoning
(~3175s/forsøg, tomt content). Re-kørt med EVAL_MAX_TOKENS=131072 → færdig på
299s/~5k tokens. Reasoning-løbskkørsel er stokastisk; harness-fix (exit 1 ved
udtømte retries + konfigurerbart budget) ligger i run-chunk-validated.sh.
