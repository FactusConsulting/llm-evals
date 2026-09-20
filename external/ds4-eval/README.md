# ds4-eval

The curated benchmark subsets from [antirez/ds4](https://github.com/antirez/ds4),
run against our own endpoints.

**142 cases, no model judges.** Every case carries an answer key and a
deterministic comparison, so a run costs one inference pass and zero judge
tokens — the opposite trade from our own knowledge suite.

| Suite | Cases | Composition |
|---|---:|---|
| `core` | 92 | 25 GPQA Diamond, 25 SuperGPQA, 25 AIME 2025, 17 defensive code review |
| `hard` | 50 | 30 MMLU-Pro, 10 OlympiadBench, 5 LiveBench, 5 NIST Juliet |
| `hard-smoke` | 12 | fixed subset of `hard` |

## Why this suite, given we already have one

Our own knowledge eval is saturated at the top: 26B Gemma, 31B Gemma and GLM-5.3
sit within 0.36 pp of each other, and our measurement precision is 0.13 pp. It
is a good regression gate and a poor ranking instrument.

These cases are not saturated, and they answer a different question: **did the
quantisation damage reasoning?** That is a live question when we serve
`UD-Q2_K_XL`. Comparing the same model at two quants on GPQA Diamond and AIME is
a direct read on it, and contamination does not interfere with that comparison
because both sides are equally contaminated.

Do not read these as leaderboard numbers. Upstream calls them "integration tests
for DwarfStar, not official benchmark distributions or leaderboard scores", and
the subsets are small enough that a few cases swing a percentage point.

## Running

```bash
./fetch_cases.py                      # writes cases.json from a pinned ds4 revision
./test_grade.py                       # 27 assertions covering the grading port
./run.py --url http://192.168.2.173:30000 --model glm5.3-flash \
         --suite core --out ../../results/<model>/ds4-core
```

`--source 'GPQA Diamond'` and `--limit N` narrow a run; `--suite hard-smoke` is
the 12-case check that the endpoint and the harness still work.

## Why cases.json is not committed

`cases.json` holds the answer keys. Committing it would put benchmark answers in
a git repository, which is exactly the path by which these suites get
contaminated into a future model's training data. Fetch it instead: the
revision is pinned in `fetch_cases.py`, so runs stay reproducible without the
keys living here.

## How faithful this is to ds4-eval

The prompts, the answer extraction and the matching are ported from
`ds4_eval.c`, so a score here means what a score from `ds4-eval` means. The port
is covered by `test_grade.py`, which asserts the behaviours the C spells out:
`</think>` stripping, last-`Answer:`-wins, prose that must not be read as a pick
("A careful look", "I'll say C"), negated distractors ("not B, so D"), leading
zeros, `\boxed{}` stripping, aliases, and COMPSEC line-set subsetting.

Three differences, all of which make our numbers a **lower bound** rather than
an inflated one:

1. **No forced think-closure.** ds4 reserves a reply budget (1024 soft / 512
   hard) and makes the model close its reasoning as it approaches the limit. We
   speak plain HTTP and cannot. A thinking model that spends the whole budget
   reasoning returns no `Answer:` line and scores zero, where ds4 would have
   nudged it into answering. Watch `truncated` in the summary — if it is not 0,
   raise `--max-tokens` before comparing anything.
2. **Sampling.** We default to `temperature 0`. ds4 uses its own top-p/min-p
   defaults and a "high" think mode.
3. **Reasoning arrives out of band.** llama.cpp returns `reasoning_content`
   separately, so we grade `content` alone. ds4 grades one string and strips
   everything before `</think>`. Same result, different plumbing.

The default token budget is 16000, matching ds4; hard-suite cases carry their
own per-case budget and override it, which is also ds4's precedence.

## Output

`results.json` holds a summary plus one record per case — expected, got, kind,
finish_reason, seconds, and the full response, so a disputed grade can be
re-read without re-running. `run-config.txt` records the exact command, the
pinned cases revision, and the date.
