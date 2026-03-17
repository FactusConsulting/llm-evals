# LLM Knowledge Evaluation Suite

Domain-specific test suites for evaluating LLM model competency in infrastructure and development topics.

## What's Here

| File | Topics | Questions | Max Score |
|------|--------|-----------|-----------|
| `infrastructure.md` | Networking, Linux, Kubernetes, Dev, OpenTofu, Ansible | 54 | 108 |
| `development.md` | Go, Rust, .NET, Python, JS/TS, Bash, PowerShell | 66 | 132 |
| **Total** | | **120** | **240** |

## How to Use

### 1. Test a Model

Open either file, select a question, and paste it into the model you're testing.

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
