# Model Evaluation Summary

Last updated: 2026-03-20

## Overall Scores

| Model | Config | Infra Score | Dev Score | Arch Score | Scenario Score | Total | % | Evaluator |
|-------|--------|-------------|-----------|------------|----------------|-------|---|-----------|
| Qwen3.5-35B-A3B Q5_K_M | 1x262144 | 225.8/240 | 255.4/280 | 153.2/160 | 48.6/60 | 683/740 | 92.3% | opus |
| Qwen3.5-35B-A3B Q5_K_M | **2x131072** | **227.4/240** | **260.6/280** | **152.6/160** | **48.0/60** | **688.6/740** | **93.1%** | opus |

## Infrastructure Scores by Section

| Model / Config | Networking | Linux | K8s | Dev | OpenTofu | Ansible | Infra Total |
|----------------|-----------|-------|-----|-----|----------|---------|-------------|
| Q5_K_M 1x262144 (mean) | 34.2/40 | 39/40 | 37/40 | 40/40 | 36.6/40 | 39/40 | 225.8/240 |
| Q5_K_M 2x131072 (mean) | 37/40 | 38.6/40 | 37.8/40 | 39.2/40 | 37.2/40 | 37.6/40 | 227.4/240 |

## Development Scores by Section

| Model / Config | Go | Rust | .NET | Python | JS/TS | Bash | PS | Dev Total |
|----------------|----|----|------|--------|-------|------|-----|-----------|
| Q5_K_M 1x262144 (mean) | 37.6/40 | 36.8/40 | 39.6/40 | 39.4/40 | 39/40 | 36.2/40 | 26.8/40 | 255.4/280 |
| Q5_K_M 2x131072 (mean) | **40/40** | 39/40 | **40/40** | 39.2/40 | 39/40 | 36.6/40 | 26.8/40 | 260.6/280 |

## Architecture Scores by Section

| Model / Config | App Arch | On-Prem | Cloud | OT | Arch Total |
|----------------|----------|---------|-------|----|------------|
| Q5_K_M 1x262144 (mean) | 39.2/40 | 36/40 | 39/40 | 39/40 | 153.2/160 |
| Q5_K_M 2x131072 (mean) | 39.2/40 | 35.4/40 | 39/40 | 39/40 | 152.6/160 |

## Scenario Scores

| Model / Config | SC1 | SC2 | SC3 | SC4 | SC5 | SC6 | SC7 | SC8 | SC9 | SC10 | Scenario Total |
|----------------|-----|-----|-----|-----|-----|-----|-----|-----|-----|------|----------------|
| Q5_K_M 1x262144 (mean) | 5/6 | 5/6 | 3.4/6 | 6/6 | 4.2/6 | 5/6 | 5/6 | 5/6 | 5/6 | 5/6 | 48.6/60 |
| Q5_K_M 2x131072 (mean) | 5/6 | 5/6 | 3.4/6 | 6/6 | 4.2/6 | 5/6 | 4.6/6 | 5/6 | 5/6 | 4.8/6 | 48.0/60 |

## 5-Run Variance — 1x262144

| Run | Infrastructure | Development | Architecture | Scenarios | Total | % |
|-----|---------------|-------------|--------------|-----------|-------|---|
| 1 | 225/240 | 252/280 | 152/160 | 48/60 | 677/740 | 91.5% |
| 2 | 225/240 | 253/280 | 152/160 | 48/60 | 678/740 | 91.6% |
| 3 | 226/240 | 257/280 | 152/160 | 49/60 | 684/740 | 92.4% |
| 4 | 228/240 | 258/280 | 154/160 | 48/60 | 688/740 | 93.0% |
| 5 | 225/240 | 257/280 | 156/160 | 50/60 | 688/740 | 93.0% |
| **Mean** | **225.8** | **255.4** | **153.2** | **48.6** | **683** | **92.3%** |

## 5-Run Variance — 2x131072

| Run | Infrastructure | Development | Architecture | Scenarios | Total | % |
|-----|---------------|-------------|--------------|-----------|-------|---|
| 1 | 226/240 | 260/280 | 152/160 | 50/60 | 688/740 | 93.0% |
| 2 | 228/240 | 261/280 | 152/160 | 48/60 | 689/740 | 93.1% |
| 3 | 227/240 | 259/280 | 152/160 | 47/60 | 685/740 | 92.6% |
| 4 | 228/240 | 262/280 | 153/160 | 47/60 | 690/740 | 93.2% |
| 5 | 228/240 | 261/280 | 154/160 | 48/60 | 691/740 | 93.4% |
| **Mean** | **227.4** | **260.6** | **152.6** | **48.0** | **688.6** | **93.1%** |

## Configuration Comparison

| Setting | 1x262144 | 2x131072 |
|---------|----------|----------|
| Context per slot | 262,144 | 131,072 |
| Parallel slots | 1 | 2 |
| Total KV cache | 262,144 | 262,144 |
| n_predict | 24,576 | 24,576 |
| Sampling | temp=0.1, top_p=0.95, top_k=20 | temp=0.1, top_p=0.95, top_k=20 |
| Hardware | 2x RTX 5060 Ti 16GB (ngl=999) | 2x RTX 5060 Ti 16GB (ngl=999) |
| Backend | llama.cpp b8373 + CUDA 13.0 | llama.cpp b8373 + CUDA 13.0 |
| Mean score | 683/740 (92.3%) | **688.6/740 (93.1%)** |
| Variance range | 11 points | **6 points** |
| Throughput | 1x (serial) | **2x (parallel)** |

## Key Findings

- **2x131072 scores equivalently or marginally better** (+5.6 points, +0.8%) with tighter variance
- **Same weaknesses persist** across both configs: PowerShell (67%), Scenario B parts (code), Networking edge cases
- **2x131072 provides 2x throughput** by serving requests in parallel with no quality penalty
- Question chunks (40-60 questions, ~3-5k tokens) fit within 131k tokens — the halved context has no impact

## Detailed Results

See the model-specific subdirectories for per-question JSON results and raw responses.

## Legend

- Score format: `points/max`
- Evaluator: `opus` = Claude Opus 4.6, `gpt` = GPT 5.4, `opus+gpt` = both agreed
