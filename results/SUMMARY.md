# Model Evaluation Summary

Last updated: 2026-03-17

## Overall Scores

| Model | Infra Score | Dev Score | Arch Score | Scenario Score | Total | % | Evaluator |
|-------|-------------|-----------|------------|----------------|-------|---|-----------|
<!-- Add rows as results come in -->
<!-- | llama-3.1-70b | 144/240 | 160/280 | 96/160 | 36/60 | 436/740 | 59% | opus+gpt | -->

## Infrastructure Scores by Section

| Model | Networking | Linux | K8s | Dev | OpenTofu | Ansible | Infra Total |
|-------|-----------|-------|-----|-----|----------|---------|-------------|
<!-- | llama-3.1-70b | 24/40 | 28/40 | 30/40 | 24/40 | 20/40 | 18/40 | 144/240 | -->

## Development Scores by Section

| Model | Go | Rust | .NET | Python | JS/TS | Bash | PS | Dev Total |
|-------|----|----|------|--------|-------|------|-----|-----------|
<!-- | llama-3.1-70b | 24/40 | 20/40 | 22/40 | 30/40 | 24/40 | 20/40 | 20/40 | 160/280 | -->

## Architecture Scores by Section

| Model | App Arch | On-Prem | Cloud | OT | Arch Total |
|-------|----------|---------|-------|----|------------|
<!-- | llama-3.1-70b | 28/40 | 24/40 | 26/40 | 18/40 | 96/160 | -->

## Scenario Scores

| Model | SC1 | SC2 | SC3 | SC4 | SC5 | SC6 | SC7 | SC8 | SC9 | SC10 | Scenario Total |
|-------|-----|-----|-----|-----|-----|-----|-----|-----|-----|------|----------------|
<!-- | llama-3.1-70b | 4/6 | 3/6 | 5/6 | 2/6 | 4/6 | 3/6 | 5/6 | 3/6 | 4/6 | 3/6 | 36/60 | -->

## Detailed Results

See the model-specific subdirectories for per-question JSON results.

## Legend

- Score format: `points/max`
- Evaluator: `opus` = Claude Opus 4.6, `gpt` = GPT 5.4, `opus+gpt` = both agreed
