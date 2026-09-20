# Results

Raw per-run eval data, one directory per model build. **The scores live in
[`../DASHBOARD.md`](../DASHBOARD.md)** — that is the only place a number is
published. Read this file only when you need the evidence behind a number.

## What a run directory holds

```
results/<model-build>/
├── chunks -> ../<other-build>/chunks   # the shared question files (or a real copy)
├── run-chunk.sh                        # the API wrapper this run used
├── run1/ … runN/
│   ├── chunk1-response.txt … chunk9-response.txt   # raw model output
│   └── <judging artefact>                          # see the table below
├── judge-summary.md                    # per-run scores, agreement, per-chunk
└── verdict.md | VERDICT.md             # the model-level conclusion
```

`chunk*-response.txt` is the bulk of this tree (~2 600 files). Nothing reads it
after judging except a re-judge or a dispute, so treat the run directories as an
archive with a couple of markdown files on top.

## How to tell what a number rests on

The judging artefact in `runN/` names the method, and the methods are not
interchangeable:

| Artefact in `runN/` | Method | Comparable to the DASHBOARD's top rows? |
|---|---|---|
| `judge.json` | two Opus judges, per-question mean(A,B), `judge-llm-eval/2.0` | yes — this is the current method |
| `judge-A.json` + `judge-B.json` | same two judges, aggregation not written out | yes, after aggregating |
| `chunk*-ratings-passA.json` | one judging pass per chunk (the GX10 vLLM campaign) | roughly — one judge, so ±2 pp |
| `chunk*-ratings.json` | the older single-judge pipeline | no — single-judge runs read ~4 pp stricter |
| nothing | responses only, never scored | no number exists |

Deltas under 1 pp between two different artefact classes are meaningless. See
[`../METHODOLOGY.md`](../METHODOLOGY.md).

## Responses on disk with no score

These builds answered the suite and were never judged. The responses are here, so
judging them costs judges but no inference:

- `qwen36-35b-a3b-q5km-STOCK-2x128k-ai-infer2` — **the deployed fleet model**
- `qwen36-35b-a3b-q5km-mtp-2x65k-ai-infer2`, `qwen36-35b-a3b-mxfp4-2x128k-ai-infer1`
- `qwen35-9b-q8_0`, `qwen35-27b-opus-distilled-q4km`

The first three carry old-pipeline `chunk*-ratings.json`; none has a `judge.json`.
**No Qwen build in this repo has been scored under the current two-judge method**,
which is why the DASHBOARD carries no head-to-head between the Qwen fleet and
GLM-5.3-Flash. That comparison is one judging round away, not one eval away.

## Directories that are not model runs

- `architect/answers.md` — the reference-answer source that
  `skills/judge-llm-eval/answers/chunk7-8-architect.md` was imported from.
- `gemma4-12b-vs-26b-agentic-loop-ai-infer2/`, `gemma4-mtp-benchmark-ai-infer2/` —
  a README each, no run data.
- `_archive/` — superseded, invalid and unjudged runs, plus the closed cross-model
  verdicts. See [`_archive/README.md`](_archive/README.md). Nothing is ever deleted
  from here; it is moved with `git mv`.

## Adding a run

`skills/judge-llm-eval/HOW-TO-DRIVE-EVAL.md` is the procedure, including the
directory layout to create and what to write where. One run is the routine; three
only when establishing a new baseline.
