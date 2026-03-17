# Results

Store evaluation results here following the schema in `result-schema.json`.

## Directory Structure

```
results/
├── result-schema.json          # JSON schema for result files
├── SUMMARY.md                  # Aggregated results across all models
├── examples/                   # Example results (for reference)
│   └── llama-3.1-70b/
│       └── N3.json
├── llama-3.1-70b/              # Results for a specific model
│   ├── N1.json
│   ├── N2.json
│   └── ...
├── qwen-2.5-72b/
│   └── ...
└── ...
```

## How to Add Results

1. **Get the answer** from the model you're testing
2. **Evaluate** using the prompt in `prompts/evaluator-prompt.md`
3. **Save** the JSON response as `results/<model-name>/<question-id>.json`
4. **Update SUMMARY.md** with the new scores

## Naming Convention

- Model directory: lowercase, hyphens instead of dots/spaces (e.g., `llama-3.1-70b`, `qwen-2.5-72b`, `mistral-large-2`)
- File name: question ID from the test suite (e.g., `N1.json`, `G7.json`, `K8.json`)
- If both evaluators rate the same answer, save as `N1-opus.json` and `N1-gpt.json`

## Getting Summary Statistics

Ask PM (or any helper):
> "Update the SUMMARY.md with results from the llama-3.1-70b folder"

Or manually calculate:
- **Per section:** Sum points / max points × 100 = percentage
- **Overall:** Total points across all sections / 240 × 100 = percentage
