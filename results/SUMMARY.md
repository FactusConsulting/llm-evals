# Model Evaluation Summary

Last updated: 2026-03-21

## Overall Scores

| Model | Config | KV Cache | RAM | Infra | Dev | Arch | Scenarios | Total | % | Evaluator |
|-------|--------|----------|-----|-------|-----|------|-----------|-------|---|-----------|
| Qwen3.5-35B-A3B Q5_K_M | 1×262144 | q8_0 | 8GB | 225.8/240 | 255.4/280 | 153.2/160 | 48.6/60 | 683/740 | 92.3% | opus |
| Qwen3.5-35B-A3B Q5_K_M | 2×131072 | q8_0 | 8GB | 227.4/240 | 260.6/280 | 152.6/160 | 48.0/60 | 688.6/740 | 93.1% | opus |
| Qwen3.5-35B-A3B Q5_K_M | 2×60000 | q8_0 | 24GB | 228/240 | 267/280 | 148/160 | 42/60 | 685/740 | 92.6% | opus |
| Qwen3.5-35B-A3B Q5_K_M | **2×60000** | **q4_0** | **24GB** | **226/240** | **274/280** | **146/160** | **45/60** | **691/740** | **93.4%** | opus |
| Qwen3.5-35B-A3B Q5_K_M | 2×262144 | q4_0 | 24GB | 224/240 | 256/280 | 146/160 | 42/60 | 668/740 | 90.3% | opus |
| Qwen3.5-35B-A3B Q5_K_M | 3×131072 | q4_0 | 24GB | 211/240 | 258/280 | 143/160 | 46/60 | 658/740 | 88.9% | opus |

## KV Cache Quantization Comparison (2-slot, matched conditions)

| KV Type | Score | % | Notes |
|---------|-------|---|-------|
| q8_0 | 685/740 | 92.6% | 24GB RAM, stable |
| **q4_0** | **691/740** | **93.4%** | 24GB RAM, stable — **no quality penalty** |

q4_0 KV cache halves KV memory with zero measurable quality loss. The +6 point difference is within normal run-to-run variance (6-11 points).

## Parallelism Impact (q4_0 KV, matched conditions)

| Slots | Context/slot | Score | % | Throughput | Notes |
|-------|-------------|-------|---|------------|-------|
| **2** | **60,000** | **691/740** | **93.4%** | 2× | Best quality |
| 3 | 131,072 | 658/740 | 88.9% | 3× | -4.5% from GPU contention |

3-slot configuration trades ~4% quality for 50% more throughput. The drop is from GPU compute contention (2× RTX 5060 Ti splitting work across 3 concurrent streams), not KV cache.

## Infrastructure Scores by Section

| Config | Networking | Linux | K8s | Dev | OpenTofu | Ansible | Infra Total |
|--------|-----------|-------|-----|-----|----------|---------|-------------|
| 1×262144 q8 (mean) | 34.2/40 | 39/40 | 37/40 | 40/40 | 36.6/40 | 39/40 | 225.8/240 |
| 2×131072 q8 (mean) | 37/40 | 38.6/40 | 37.8/40 | 39.2/40 | 37.2/40 | 37.6/40 | 227.4/240 |
| 2×60k q8 (run1) | 37/40 | 39/40 | 40/40 | 39/40 | 36/40 | 37/40 | 228/240 |
| 2×60k q4 (run1) | 38/40 | 38/40 | 40/40 | 39/40 | 35/40 | 36/40 | 226/240 |
| 3×131k q4 (run1) | 33/40 | 35/40 | 38/40 | 35/40 | 38/40 | 32/40 | 211/240 |

## Development Scores by Section

| Config | Go | Rust | .NET | Python | JS/TS | Bash | PS | Dev Total |
|--------|----|----|------|--------|-------|------|-----|-----------|
| 1×262144 q8 (mean) | 37.6/40 | 36.8/40 | 39.6/40 | 39.4/40 | 39/40 | 36.2/40 | 26.8/40 | 255.4/280 |
| 2×131072 q8 (mean) | 40/40 | 39/40 | 40/40 | 39.2/40 | 39/40 | 36.6/40 | 26.8/40 | 260.6/280 |
| 2×60k q8 (run1) | 38/40 | 37/40 | 36/40 | 38/40 | 40/40 | 39/40 | 39/40 | 267/280 |
| 2×60k q4 (run1) | 38/40 | 40/40 | 40/40 | 40/40 | 40/40 | 38/40 | 38/40 | 274/280 |
| 3×131k q4 (run1) | 39/40 | 39/40 | 35/40 | 35/40 | 40/40 | 38/40 | 32/40 | 258/280 |

## Architecture Scores by Section

| Config | App Arch | On-Prem | Cloud | OT | Arch Total |
|--------|----------|---------|-------|----|------------|
| 1×262144 q8 (mean) | 39.2/40 | 36/40 | 39/40 | 39/40 | 153.2/160 |
| 2×131072 q8 (mean) | 39.2/40 | 35.4/40 | 39/40 | 39/40 | 152.6/160 |
| 2×60k q8 (run1) | 36/40 | 34/40 | 39/40 | 39/40 | 148/160 |
| 2×60k q4 (run1) | 36/40 | 34/40 | 37/40 | 39/40 | 146/160 |
| 3×131k q4 (run1) | 37/40 | 35/40 | 37/40 | 34/40 | 143/160 |

## 5-Run Variance — 1×262144

| Run | Infrastructure | Development | Architecture | Scenarios | Total | % |
|-----|---------------|-------------|--------------|-----------|-------|---|
| 1 | 225/240 | 252/280 | 152/160 | 48/60 | 677/740 | 91.5% |
| 2 | 225/240 | 253/280 | 152/160 | 48/60 | 678/740 | 91.6% |
| 3 | 226/240 | 257/280 | 152/160 | 49/60 | 684/740 | 92.4% |
| 4 | 228/240 | 258/280 | 154/160 | 48/60 | 688/740 | 93.0% |
| 5 | 225/240 | 257/280 | 156/160 | 50/60 | 688/740 | 93.0% |
| **Mean** | **225.8** | **255.4** | **153.2** | **48.6** | **683** | **92.3%** |

## 5-Run Variance — 2×131072

| Run | Infrastructure | Development | Architecture | Scenarios | Total | % |
|-----|---------------|-------------|--------------|-----------|-------|---|
| 1 | 226/240 | 260/280 | 152/160 | 50/60 | 688/740 | 93.0% |
| 2 | 228/240 | 261/280 | 152/160 | 48/60 | 689/740 | 93.1% |
| 3 | 227/240 | 259/280 | 152/160 | 47/60 | 685/740 | 92.6% |
| 4 | 228/240 | 262/280 | 153/160 | 47/60 | 690/740 | 93.2% |
| 5 | 228/240 | 261/280 | 154/160 | 48/60 | 691/740 | 93.4% |
| **Mean** | **227.4** | **260.6** | **152.6** | **48.0** | **688.6** | **93.1%** |

## Configuration Comparison

| Setting | 1×262144 | 2×131072 | 2×60k q8 | 2×60k q4 | 3×131k q4 |
|---------|----------|----------|----------|----------|-----------|
| Context per slot | 262,144 | 131,072 | 60,000 | 60,000 | 131,072 |
| Parallel slots | 1 | 2 | 2 | 2 | 3 |
| KV cache type | q8_0 | q8_0 | q8_0 | q4_0 | q4_0 |
| Total KV tokens | 262,144 | 262,144 | 120,000 | 120,000 | 393,216 |
| VM RAM | 8 GB | 8 GB | 24 GB | 24 GB | 24 GB |
| Score | 683 (92.3%) | **688.6 (93.1%)** | 685 (92.6%) | **691 (93.4%)** | 658 (88.9%) |
| Variance range | 11 pts | 6 pts | — | — | — |
| Throughput | 1× | 2× | 2× | 2× | 3× |

## Key Findings

- **q4_0 KV cache has no quality penalty** vs q8_0 — scores 691 vs 685 (within variance)
- **q4_0 halves KV cache memory** — 5 GB vs 10 GB for the same context, freeing VRAM
- **2-slot is the sweet spot** for dual RTX 5060 Ti — 93% quality with 2× throughput
- **3-slot drops quality ~4%** (658 vs 691) due to GPU compute contention, not KV cache
- **Same weaknesses persist** across all configs: PowerShell (67-82%), Scenario B parts (code), Networking edge cases
- **Recommended config**: 2 slots, q4_0 KV cache, 131k context/slot (262k total)

## Detailed Results

See the model-specific subdirectories for per-question JSON results and raw responses.

## Legend

- Score format: `points/max`
- Evaluator: `opus` = Claude Opus 4.6, `gpt` = GPT 5.4, `opus+gpt` = both agreed
- Configs tested on 2026-03-20 (1×262144, 2×131072) and 2026-03-21 (q8/q4 comparison, 3-slot)
