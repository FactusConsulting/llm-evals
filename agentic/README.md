# Agentic Evaluation Suite

Tests a model's ability to **do work** — use tools, solve multi-step problems, recover from errors, and avoid loops.

## How it differs from the knowledge eval

| Knowledge Eval | Agentic Eval |
|---------------|-------------|
| Tests what a model *knows* | Tests what a model *does* |
| Q&A format, rated by a judge | Task format, verified programmatically |
| Single-turn responses | Multi-turn tool-calling loops |
| Speed doesn't matter | Timeboxed execution |

## Tiers

- **Tier 1** (AG1-AG10): Basic tool use, ~2 min each, 10 max steps
- **Tier 2** (AG11-AG20): Multi-step problem solving, ~5 min each, 30 max steps
- **Tier 3** (AG21-AG30): Complex agentic scenarios, ~10 min each, 50 max steps

## Scoring (per task, max 10 pts)

| Dimension | Points | What it measures |
|-----------|--------|-----------------|
| Completion | 0-4 | Did it achieve the goal? |
| Efficiency | 0-2 | Steps taken vs minimum possible |
| Recovery | 0-2 | Handled errors without spiraling? |
| Quality | 0-2 | Clean result, no junk artifacts? |

**Penalties:** -1 per repeated identical tool call, -2 for giving up without trying

## Running

```bash
# Single task against a model
python3 harness.py --model-url http://192.168.2.171:8001 --model-name qwen3.5-9b --task AG1

# All Tier 1 tasks
python3 harness.py --model-url http://192.168.2.171:8001 --model-name qwen3.5-9b --tier 1

# All tasks against multiple models
./run-agentic-evals.sh
```

## Adding tasks

1. Create `tasks/AGxx.yaml` with setup, goal, tools, and verify
2. Create `fixtures/AGxx/` with any pre-built files
3. Create `verify/AGxx.sh` that exits 0 on success
