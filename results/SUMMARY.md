# Model Evaluation Summary

Last updated: 2026-03-17

## Overall Scores

| Model | Infra Score | Dev Score | Total | % | Evaluator |
|-------|-------------|-----------|-------|---|-----------|
<!-- Add rows as results come in -->
<!-- | llama-3.1-70b | 72/108 | 80/132 | 152/240 | 63% | opus+gpt | -->

## Infrastructure Scores by Section

| Model | Networking | Linux | K8s | Dev | OpenTofu | Ansible | Infra Total |
|-------|-----------|-------|-----|-----|----------|---------|-------------|
<!-- | llama-3.1-70b | 16/20 | 14/20 | 18/20 | 12/16 | 8/16 | 14/16 | 72/108 | -->

## Development Scores by Section

| Model | Go | Rust | .NET | Python | JS/TS | Bash | PS | Dev Total |
|-------|----|----|------|--------|-------|------|-----|-----------|
<!-- | llama-3.1-70b | 14/20 | 10/20 | 12/20 | 18/20 | 14/20 | 8/16 | 4/16 | 80/132 | -->

## Detailed Results

See the model-specific subdirectories for per-question JSON results.

## Legend

- Score format: `points/max`
- Evaluator: `opus` = Claude Opus 4.6, `gpt` = GPT 5.4, `opus+gpt` = both agreed
