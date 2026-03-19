# Model Evaluation Summary

Last updated: 2025-07-24

## Overall Scores

| Model | Infra Score | Dev Score | Arch Score | Scenario Score | Total | % | Evaluator |
|-------|-------------|-----------|------------|----------------|-------|---|-----------|
| Qwen3.5-35B-A3B Q5_K_M (5-run mean) | 225.8/240 | 255.4/280 | 153.2/160 | 48.6/60 | 683/740 | 92.3% | opus |

## Infrastructure Scores by Section

| Model | Networking | Linux | K8s | Dev | OpenTofu | Ansible | Infra Total |
|-------|-----------|-------|-----|-----|----------|---------|-------------|
| Qwen3.5-35B Q5_K_M (mean) | 34.2/40 | 39/40 | 37/40 | 40/40 | 36.6/40 | 39/40 | 225.8/240 |

## Development Scores by Section

| Model | Go | Rust | .NET | Python | JS/TS | Bash | PS | Dev Total |
|-------|----|----|------|--------|-------|------|-----|-----------|
| Qwen3.5-35B Q5_K_M (mean) | 37.6/40 | 36.8/40 | 39.6/40 | 39.4/40 | 39/40 | 36.2/40 | 26.8/40 | 255.4/280 |

## Architecture Scores by Section

| Model | App Arch | On-Prem | Cloud | OT | Arch Total |
|-------|----------|---------|-------|----|------------|
| Qwen3.5-35B Q5_K_M (mean) | 39.2/40 | 36/40 | 39/40 | 39/40 | 153.2/160 |

## Scenario Scores

| Model | SC1 | SC2 | SC3 | SC4 | SC5 | SC6 | SC7 | SC8 | SC9 | SC10 | Scenario Total |
|-------|-----|-----|-----|-----|-----|-----|-----|-----|-----|------|----------------|
| Qwen3.5-35B Q5_K_M (mean) | 5/6 | 5/6 | 3.4/6 | 6/6 | 4.2/6 | 5/6 | 5/6 | 5/6 | 5/6 | 5/6 | 48.6/60 |

## 5-Run Variance

| Run | Infrastructure | Development | Architecture | Scenarios | Total | % |
|-----|---------------|-------------|--------------|-----------|-------|---|
| 1 | 225/240 | 252/280 | 152/160 | 48/60 | 677/740 | 91.5% |
| 2 | 225/240 | 253/280 | 152/160 | 48/60 | 678/740 | 91.6% |
| 3 | 226/240 | 257/280 | 152/160 | 49/60 | 684/740 | 92.4% |
| 4 | 228/240 | 258/280 | 154/160 | 48/60 | 688/740 | 93.0% |
| 5 | 225/240 | 257/280 | 156/160 | 50/60 | 688/740 | 93.0% |
| **Mean** | **225.8** | **255.4** | **153.2** | **48.6** | **683** | **92.3%** |

## Configuration

- **Model:** Qwen3.5-35B-A3B (Bartowski Q5_K_M, q8_0 KV cache)
- **Context:** 262,144 tokens, n_predict=24,576
- **Sampling:** temp=0.1, top_p=0.95, top_k=20
- **Hardware:** 2x RTX 5060 Ti 16GB (ngl=999, all layers GPU)
- **Backend:** llama.cpp b8373 + CUDA 13.0
- **Avg. time per run:** ~18 minutes (9 chunks)

## Detailed Results

See the model-specific subdirectories for per-question JSON results.

## Legend

- Score format: `points/max`
- Evaluator: `opus` = Claude Opus 4.6, `gpt` = GPT 5.4, `opus+gpt` = both agreed
