# How to drive a model evaluation end-to-end

> Audience: an AI agent (Claude Opus, GPT-5, future you) tasked with evaluating a new model on this suite.
>
> Goal: produce a stable, reproducible quality score for a model that can be compared against existing baselines without judge-variance noise drowning out real differences.
>
> Estimated time: ~60-90 minutes of agent + compute work for a complete 3-run evaluation with judging and verdict.

## Mental model

You are an **orchestrator**. You don't score answers yourself — that introduces context pollution and judge bias. You spawn sub-agents to do the actual work, collect their outputs, and aggregate.

Three phases:

1. **Generate responses** — the model under test answers the eval suite (3 runs, 9 chunks each)
2. **Judge responses** — two parallel Opus judges score each run independently using a fixed rubric + reference answer key
3. **Aggregate + report** — compute mean(A,B), produce judge.json + summary.md + verdict.md, commit

## Phase 0 — Pre-flight checks (do this first, every time)

```bash
# Confirm model is up and serving
curl -sS -H "Authorization: Bearer $KEY" https://<host>/v1/models | jq -r '.data[].id'

# Confirm reasoning_content works (relevant for thinking models)
curl -sS https://<host>/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"<alias>","messages":[{"role":"user","content":"What is 17*23?"}],"max_tokens":500}' \
  | jq '.choices[0].message | keys'
# Should include "reasoning_content" if model supports thinking

# Confirm chat template SHA + build_info
curl -sS -H "Authorization: Bearer $KEY" https://<host>/props \
  | python3 -c "import json,sys,hashlib; r=json.load(sys.stdin); print('build_info:',r['build_info']); print('template_sha:',hashlib.sha256(r['chat_template'].encode()).hexdigest()[:16])"
```

Write down: build_info, model_path, chat_template_sha, GGUF md5. These go in `verdict.md` later.

## Phase 1 — Generate responses (3 runs × 9 chunks)

### 1a. Set up the model directory

```bash
cd /home/lars/source/llm-evals
MODEL_DIR="results/<descriptive-model-name>"   # e.g. gemma4-4b-e4b-f16-turbo4-ai-infer2
mkdir -p $MODEL_DIR/run{1,2,3}

# Symlink chunks (the question files are shared across all model evals)
ln -s ../gemma4-26b-q6k/chunks $MODEL_DIR/chunks

# Create run-chunk.sh wrapper pointing at the model's API
cat > $MODEL_DIR/run-chunk.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-validated.sh" \
  "$1" "$2" \
  "http://<host-ip>:8001/v1/chat/completions" \
  "<api-key>" \
  "<model-alias>"
SH
chmod +x $MODEL_DIR/run-chunk.sh
```

The `run-chunk-validated.sh` script handles anti-cache nonces and validation that all expected question IDs are present in the response. **Use it always.** Don't shortcut by calling the API directly — you'll lose validation and may get cached responses.

### 1b. Run the eval

**Always run 3 runs, never just 1.** Single-run scores have ~1pp stochastic variance from temperature sampling. Three runs gives a usable mean.

**Don't run more than 3 unless you suspect something specific** — diminishing returns past 3, and the 0.7pp typical range is at the noise floor.

```bash
# Use a background bash task for the eval — it takes ~30 min for 3 runs × 9 chunks
# Make sure NOTHING ELSE is hitting the same model server during the eval
# (slot contention from openclaw or opencode will roughly halve throughput AND
#  inject random chunks where the model was waiting on a busy slot — you'll see
#  variance balloon)

cd /home/lars/source/llm-evals && bash -c '
MODEL_DIR="results/<model-name>"
CHUNKS=(chunk1-networking-linux.txt chunk2-k8s-dev.txt chunk3-opentofu-ansible.txt
        chunk4-go-rust.txt chunk5-dotnet-python.txt chunk6-js-bash-powershell.txt
        chunk7-apparch-onprem.txt chunk8-cloud-ot.txt chunk9-scenarios.txt)
for run in 1 2 3; do
  for chunk in "${CHUNKS[@]}"; do
    n=$((... index ...))
    out="$MODEL_DIR/run$run/chunk${n}-response.txt"
    [[ -s $out ]] && ! grep -q ERROR "$out" && continue
    "$MODEL_DIR/run-chunk.sh" "$MODEL_DIR/chunks/$chunk" "$out"
  done
done
' 2>&1 | tee /tmp/eval-progress.log &
```

Wait for completion. Spot-check that all 27 chunk-response files exist and are non-empty. Grep for `ERROR` strings — should be zero.

### 1c. Run loop-detection (separate suite)

```bash
cd loop-detection
LLAMA_API_KEY="<key>" ./run-eval.sh \
  --model-url http://<host>:8001 \
  --model-name <model-name>-run1 \
  --max-tokens 8192 --temperature 0.1
```

Records word counts + automated spiral flags per scenario. Single run is enough for loop-detection — it's about behavior not accuracy.

## Phase 2 — Judge the responses

### 2a. Spawn 6 parallel Opus judge agents (2 per run × 3 runs)

This is the **critical step** that gives stable scores. **Always two judges per run.** Single judge has 2-4pp drift; two judges' mean has ~0.5pp drift.

For each judge agent, use the prompt template at `skills/judge-llm-eval/prompts/judge.md`. Key things to drill into the agent's head:

1. **Default to pass.** The model is correct unless you can point to a concrete error.
2. **Reference is one valid solution, NOT a contract.** Different valid alternatives are still pass.
3. **Use `alternative_acceptable: true` often** — expect 10-30% of questions to have it. <5% means you're being too strict.
4. **Two-phase evaluation**: first ask "does this solve the problem?", then use reference to fact-check specific claims.

The judge reads:
- `skills/judge-llm-eval/prompts/rubric.md` (the rubric)
- `skills/judge-llm-eval/answers/chunk{1..9}-*.md` (reference answer key — for fact-checking only)
- `results/gemma4-26b-q6k/chunks/chunk{1..9}-*.txt` (the questions)
- `results/<model>/run<N>/chunk{1..9}-response.txt` (the model's answers to score)

The judge writes a single JSON object to `/tmp/judge-{a,b}-v2-run<N>.json` with this shape:

```json
{
  "judge": "A",
  "run": 1,
  "model_dir": "<model-name>",
  "chunks": {
    "1": {
      "chunk_name": "chunk1-networking-linux",
      "questions": {
        "N1": {
          "rating": "pass",
          "points": 2,
          "alternative_acceptable": false,
          "phase1_solved": "yes",
          "phase2_factual_error": "none",
          "justification": "one sentence"
        },
        ...
      }
    },
    ...
    "9": { "questions": { "SC1-A": {...}, ..., "SC10-C": {...} } }
  }
}
```

**Always launch all 6 judges in parallel** (one batch of 6 Agent tool calls in a single message). They each take ~6-8 minutes; in parallel that's ~8 min wall time. Sequential would be ~45 min.

### 2b. Aggregate to judge.json per run

After all 6 judges finish, run the aggregator (this Python snippet handles disagreement resolution via mean(A,B) per question):

```python
import json
from pathlib import Path
from datetime import datetime, timezone

OUTDIR = Path("results/<model-name>")

for run in [1, 2, 3]:
    a = json.loads(Path(f"/tmp/judge-a-v2-run{run}.json").read_text())
    b = json.loads(Path(f"/tmp/judge-b-v2-run{run}.json").read_text())
    
    chunks = {}
    total = {"q":0,"pass":0,"partial":0,"fail":0,"pts":0,"max":0,"alt":0}
    chunk9_pa = {"pts":0,"max":0}
    chunk9_pb = {"pts":0,"max":0}
    chunk9_pc = {"pts":0,"max":0}
    
    for ck in sorted(set(a["chunks"].keys()) | set(b["chunks"].keys()), key=int):
        qa = a["chunks"].get(ck, {}).get("questions", {})
        qb = b["chunks"].get(ck, {}).get("questions", {})
        chunk_data = {"chunk_name": a["chunks"].get(ck, {}).get("chunk_name", f"chunk{ck}"),
                      "questions": {}}
        c_pts = c_max = c_pass = c_part = c_fail = c_alt = 0
        
        for qid in sorted(set(qa.keys()) | set(qb.keys())):
            ra, rb = qa.get(qid, {}), qb.get(qid, {})
            pa, pb = int(ra.get("points", 0)), int(rb.get("points", 0))
            mean_pts = (pa + pb) / 2.0
            
            if ra.get("rating") == rb.get("rating"):
                final_rating, final_pts, decided = ra.get("rating", "fail"), pa, "agreement"
            else:
                if mean_pts >= 1.5:   final_rating, final_pts = "pass", 2
                elif mean_pts >= 0.5: final_rating, final_pts = "partial", 1
                else:                 final_rating, final_pts = "fail", 0
                decided = "mean_of_judges"
            
            alt = ra.get("alternative_acceptable") or rb.get("alternative_acceptable")
            chunk_data["questions"][qid] = {
                "rating": final_rating, "points": final_pts,
                "alternative_acceptable": alt, "decided_by": decided,
                "judge_a": {"rating": ra.get("rating"), "points": pa,
                            "justification": ra.get("justification", "")[:200]},
                "judge_b": {"rating": rb.get("rating"), "points": pb,
                            "justification": rb.get("justification", "")[:200]},
            }
            c_pts += final_pts; c_max += 2
            if final_rating == "pass": c_pass += 1
            elif final_rating == "partial": c_part += 1
            else: c_fail += 1
            if alt: c_alt += 1
            
            if ck == "9":
                if qid.endswith("-A"): chunk9_pa["pts"] += final_pts; chunk9_pa["max"] += 2
                elif qid.endswith("-B"): chunk9_pb["pts"] += final_pts; chunk9_pb["max"] += 2
                elif qid.endswith("-C"): chunk9_pc["pts"] += final_pts; chunk9_pc["max"] += 2
        
        chunk_data["score"] = {"questions": len(chunk_data["questions"]), "pass": c_pass,
                                "partial": c_part, "fail": c_fail,
                                "points": c_pts, "max_points": c_max,
                                "percentage": round(100*c_pts/c_max, 2),
                                "alternative_acceptable": c_alt}
        chunks[ck] = chunk_data
        total["q"] += len(chunk_data["questions"])
        total["pass"] += c_pass; total["partial"] += c_part; total["fail"] += c_fail
        total["pts"] += c_pts; total["max"] += c_max; total["alt"] += c_alt
    
    out = {
        "model": "<model-name>",
        "run": run,
        "judged_at": datetime.now(timezone.utc).isoformat(),
        "skill_version": "judge-llm-eval/2.0",
        "judges": {"judge_a": "claude-opus-4-6", "judge_b": "claude-opus-4-6"},
        "chunks": chunks,
        "chunk9_breakdown": {
            "part_a": {**chunk9_pa, "pct": round(100*chunk9_pa["pts"]/chunk9_pa["max"], 1)},
            "part_b": {**chunk9_pb, "pct": round(100*chunk9_pb["pts"]/chunk9_pb["max"], 1)},
            "part_c": {**chunk9_pc, "pct": round(100*chunk9_pc["pts"]/chunk9_pc["max"], 1)},
        },
        "totals": {
            "questions_scored": total["q"],
            "pass": total["pass"], "partial": total["partial"], "fail": total["fail"],
            "points": total["pts"], "max_points": total["max"],
            "percentage": round(100*total["pts"]/total["max"], 2),
            "alternative_acceptable": total["alt"],
        },
    }
    (OUTDIR / f"run{run}" / "judge.json").write_text(json.dumps(out, indent=2))
```

### 2c. Validate Part B code deterministically

```bash
python3 skills/judge-llm-eval/validators/validate-part-b.py \
  results/<model-name>/run<N>/chunk9-response.txt
```

This runs `terraform fmt -check`, `kubectl apply --dry-run=client`, `shellcheck`, `python -m py_compile`, `jq -n`, `python yaml.safe_load_all` on extracted code blocks. Returns ✓/✗/unvalidated per scenario.

Use this as a hard signal: if the validator says ✗ but the judges said pass, audit those responses — judges may have missed a real syntax error.

## Phase 3 — Aggregate + report

### 3a. Compute the cross-run mean and verdict

```python
runs = [json.loads(Path(f"results/{model}/run{i}/judge.json").read_text()) for i in [1,2,3]]
pcts = [r["totals"]["percentage"] for r in runs]
mean_pct = sum(pcts) / 3
range_pct = max(pcts) - min(pcts)
print(f"Mean: {mean_pct:.2f}%, range: {range_pct:.2f}pp")
```

If `range_pct > 1.5pp`, something's wrong — typical stable scoring gives 0.5-0.9pp. Possible causes:
- Concurrent traffic on the model server during eval (slot contention)
- Judges had wildly different rubric interpretations (check inter-judge agreement % in the JSON)
- Real model variance (rare — only happens with high temperature settings or unstable quantization)

### 3b. Write `judge-summary.md` and `verdict.md`

Use the existing files at `results/gemma4-26b-q6k-458k-turbo4-v2-ai-infer2/{judge-summary.md,verdict.md}` as templates. Key sections:

- Per-run table (score, %, pass/partial/fail, alt_acceptable, agreement)
- Cross-run mean + range
- Per-chunk percentages
- Chunk 9 Part A/B/C breakdown
- Persistent failure modes (questions that fail in all runs — these are real model limits)
- Comparison with baseline (the current baseline is gemma4-26b-q6k v2 at 98.56%)
- Hardware budget (VRAM, slots, context)
- Production decision

### 3c. Compare with baselines

The current baselines are in `results/`:
- `gemma4-26b-q6k-458k-turbo4-v2-ai-infer2/verdict.md` — 98.56% (baseline)
- `gemma4-31b-q4km-256k-turbo4-ai-infer2/` and `gemma4-31b-q5km-160k-turbo4-ai-infer2/` — 31B at lower precision
- `gemma4-26b-q5kl-524k-turbo4/` — 26B at Q5_K_L
- `gemma4-26b-q6k/` — 26B Q6_K on old b8667 template (pre-baseline)

Note that older baselines were judged with single ad-hoc Opus and have ±2pp uncertainty. **Don't compare absolute numbers tightly** — instead compare via "the gap between the new model and the v2 baseline is X pp" computed with the SAME judging methodology.

If you're comparing a new model against the v2 baseline using the same /judge skill, deltas of >1pp are real, deltas <1pp are noise.

## Phase 4 — Commit

```bash
cd /home/lars/source/llm-evals
git add results/<model-name>/ loop-detection/results/<model-name>-run1/
git commit -m "feat(eval): <model-name> baseline — mean X%, range Y pp"
git push origin main
```

## Common pitfalls (read before you start)

1. **Don't run only 1 judge.** Single-judge scores have ±2pp drift. Always two parallel judges.
2. **Don't let other workloads hit the model server during eval.** Slot contention slows eval and can cause partial timeouts. Coordinate with the user that the server is yours.
3. **Don't skip the loop-detection eval.** It catches a different failure mode than knowledge accuracy and is fast (~10 min).
4. **Don't use the validator output as the ONLY signal for Part B.** Use it as a hard check ("this code is syntactically broken → cannot be pass"), not as a complete judgment.
5. **Don't compare new models to old (pre-v2) baselines on absolute numbers.** Always re-judge the baseline with the same /judge skill if you want a fair comparison.
6. **Don't mix runs across servers.** If you're testing model X on ai-infer2, all 3 runs must be on ai-infer2. Cross-server comparison adds an unwanted variable.
7. **Reference answers are gold standard, NOT contract.** If you find yourself spending time updating reference answers to be more accurate after a run, you're doing it wrong — the rubric says judges should accept valid alternatives via `alternative_acceptable`. Update the rubric, not the answers.
8. **Don't read full sub-agent output transcripts.** They're huge (100k+ tokens) and will overflow your context. Trust the agent's summary; if you need details, look at the JSON output file the agent wrote.

## Files you will create per model

```
results/<model-name>/
├── chunks → ../<some-baseline>/chunks    # symlink to shared questions
├── run-chunk.sh                          # API wrapper script
├── run1/
│   ├── chunk1-response.txt ... chunk9-response.txt
│   └── judge.json
├── run2/  (same structure)
├── run3/  (same structure)
├── judge-summary.md                      # per-run + cross-run scores
└── verdict.md                            # model-level verdict + hardware + decision

loop-detection/results/<model-name>-run1/
├── LD1-branch-audit-<timestamp>-response.txt
├── LD1-branch-audit-<timestamp>-score.json
└── ... (12 scenarios × 2 files)
```

## What "good" looks like

| Metric | Healthy | Suspicious | Bad |
|---|---|---|---|
| Mean across 3 runs | model-dependent | — | — |
| Range across 3 runs | 0.4-0.9 pp | 1.0-1.5 pp | >1.5 pp |
| Inter-judge agreement | 95-98% | 90-94% | <90% |
| `alternative_acceptable` rate | 10-20% | 5-9% | <5% (judges too strict) or >30% (judges too loose) |
| Per-judge variance from mean | <0.5 pp | 0.5-1.0 pp | >1.0 pp |
| Validator agreement with judges on Part B | >80% | 60-80% | <60% |

If you see "Bad" numbers, investigate — usually it's the judges being too strict on a specific chunk or a real bug in the answer extraction. The pre-v2 strict-rubric run on this same model gave 90.99% with 0.48pp range and 88-92% agreement, which looks fine on paper but is wrong (artificially low absolute score because judges used reference as checklist). After fixing the prompt to "default to pass", scores climbed to 98.56% with similar variance — that's the baseline you should expect for a strong 26B model.
