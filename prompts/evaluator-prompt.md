# Evaluator Prompt

Use this prompt when pasting a model's answer into an evaluator (Claude Opus 4.6 or GPT 5.4).

---

**System prompt:**
```
You are an expert evaluator of technical answers. You will receive a question with its expected answer, a rating guide, and a model's actual answer. Rate the answer strictly using the rubric. Respond ONLY with valid JSON — no markdown, no explanation outside the JSON.
```

**User prompt:**
```
Rate the following answer. Respond with ONLY this JSON schema, filled in:

```json
{
  "evaluator": "<your model name>",
  "evaluator_version": "<your version>",
  "question_id": "<question ID>",
  "section": "<section name>",
  "difficulty": "<easy|medium|hard>",
  "model_tested": "<name of model being tested>",
  "rating": "<pass|partial|fail>",
  "points": <0, 1, or 2>,
  "max_points": 2,
  "key_points_correct": ["<list what the model got right>"],
  "key_points_missing": ["<list what the model missed>"],
  "key_points_wrong": ["<list what the model got wrong>"],
  "brief_justification": "<1-2 sentence justification for the rating>"
}
```

**Question ID:** {question_id}
**Section:** {section}
**Difficulty:** {difficulty}

**Question:**
{paste the full question}

**Expected Answer (for reference):**
{paste the expected answer / key points from the test suite}

**Rating Guide:**
- ✅ Pass (2 pts): Correct, complete, demonstrates understanding
- ⚠️ Partial (1 pt): Mostly correct but missing key details or minor error
- ❌ Fail (0 pts): Incorrect, significantly incomplete, or misunderstanding

**Model's Answer to Rate:**
{paste the model's answer here}
```

---

## Important Notes

- The evaluator must respond with **pure JSON only** — no markdown fencing, no preamble
- If the evaluator wraps the JSON in ```json blocks, strip them before saving
- Save results to `results/<model-name>/<question-id>.json`
- Use consistent model names (e.g., `llama-3.1-70b`, `qwen-2.5-72b`, `mistral-large`)
