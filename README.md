# LLM Knowledge Evaluation Suite

Domain-specific test suites for evaluating LLM model competency in infrastructure, development, and architecture topics.

## 👉 Start here

- **[TESTING.md](TESTING.md)** — short overview of how we test models (the multi-judge approach + commands)
- **[HOW-TO-DRIVE-EVAL.md](HOW-TO-DRIVE-EVAL.md)** — detailed runbook for an AI agent (or you) to drive a full model evaluation end-to-end
- **[METHODOLOGY.md](METHODOLOGY.md)** — why we use the multi-judge architecture and what we tried that didn't work
- **[skills/judge-llm-eval/](skills/judge-llm-eval/)** — the Claude Code skill that orchestrates judging (rubric + reference answers + validators)

**Per-model results + the vLLM-vs-llama.cpp comparison** → **[DASHBOARD.md](DASHBOARD.md)** (one row per model, latest generation, with the GX10 vLLM campaign deltas). Knowledge high-water-mark is currently Qwen3.6-27B BF16 (vLLM) at 99.05%.

## What's Here

| File | Topics | Questions | Max Score |
|------|--------|-----------|-----------|
| `infrastructure.md` | Networking, Linux, Kubernetes, Dev, OpenTofu, Ansible | 120 | 240 |
| `development.md` | Go, Rust, .NET, Python, JS/TS, Bash, PowerShell | 140 | 280 |
| `architecture.md` | Application, On-Prem, Cloud, OT Architecture | 80 | 160 |
| `scenarios.md` | Cross-domain scenarios (3 parts each) | 10 | 60 |
| **Total** | | **350** | **740** |

## Reference Answers

The `results/architect/` directory contains answers from the architect agent, which can serve as a reference baseline for evaluating other models.

## How to Use

### 1. Test a Model

Open any test suite file, select a question, and paste it into the model you're testing.

### 2. Rate the Answer

Use this prompt with a strong evaluator model (Claude Opus 4.6 or GPT 5.4):

```
Rate the following answer using the scoring guide below.

**Question:** {paste question}

**Answer to rate:** {paste model's answer}

**Scoring Guide:**
| Rating | Criteria |
|--------|----------|
| ✅ Pass | Correct, complete, and demonstrates understanding |
| ⚠️ Partial | Mostly correct but missing key details or contains a minor error |
| ❌ Fail | Incorrect, significantly incomplete, or demonstrates misunderstanding |

Give your rating for each part of the question, then calculate the score:
✅ = 2 points, ⚠️ = 1 point, ❌ = 0 points
```

### 3. Compare Evaluators

For important results, run the same answer through **both** evaluator models (Claude Opus + GPT 5.4) and compare their ratings. If they disagree significantly, the answer is likely in a gray area.

## Evaluation Workflow

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Pick        │     │ Paste question   │     │ Copy answer     │
│ question    │────▶│ into model being │────▶│ into evaluator  │
│ from .md    │     │ tested           │     │ (Opus/GPT 5.4)  │
└─────────────┘     └──────────────────┘     └────────┬────────┘
                                                       │
                                              ┌────────▼────────┐
                                              │ Evaluator rates  │
                                              │ with rubric      │
                                              └────────┬────────┘
                                                       │
                                    ┌──────────────────┼──────────────────┐
                                    │                  │                  │
                              ┌─────▼─────┐    ┌──────▼──────┐    ┌─────▼──────┐
                              │ Rating    │    │ Rating      │    │ Compare    │
                              │ from Opus │    │ from GPT    │    │ scores     │
                              └───────────┘    └─────────────┘    └────────────┘
```

## Scoring

| Score | Interpretation |
|-------|----------------|
| 90%+ | Excellent — model is strong in this domain |
| 70-89% | Good — competent but missing depth in some areas |
| 50-69% | Weak — significant gaps |
| <50% | Poor — unreliable for this domain |

## Contributing

Add new questions by following the existing format:
- Section header with question number and difficulty (`Easy`, `Medium`, `Hard`)
- Clear, unambiguous question
- Update the scoring table at the bottom of the file

## License

MIT — use freely for evaluating any model.
