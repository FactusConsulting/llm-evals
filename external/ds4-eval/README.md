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
./test_grade.py && ./test_run.py      # grading port + runner, mock server only
./run.py --url http://192.168.2.173:30000 --model glm5.3-flash \
         --suite core --mode gate --out ../../results/<model>/ds4-core-gate
```

`--source 'GPQA Diamond'` and `--limit N` narrow a run; `--suite hard-smoke` is
the 12-case check that the endpoint and the harness still work.

**For a reasoning model, give it far more than you think and raise the timeout
with it.** `--max-tokens 98304 --timeout 7200` is what GLM-5.3-Flash needs here.

## Gate, measure, served

`--mode` is three named sampling presets, all with a **fixed, per-case nonce** in
the system prompt (see below):

- **`gate`** — temperature 0, seed 0. A deterministic run: the same build against
  the same cases produces the same transcripts. Use this for regression —
  any difference between two gate runs means the build changed something,
  not that the sampler got lucky.
- **`measure`** — ds4's own defaults (temperature 1.0, top_p 1.0, min_p 0.05),
  seed taken from `--seed`. Call it once per seed (`--seed 1`, `--seed 2`, …,
  `--seed N`) to get N honest samples of the model's real variance, then feed
  the N run directories to `compare.py`.
- **`served`** — sends no sampling fields at all, so the endpoint answers with
  the sampling its own model card configures; seed from `--seed`. Use this to
  compare **different models as they are actually deployed**: each runs its own
  recipe (GLM, DeepSeek and Qwen ship different ones) rather than one recipe
  imposed on all. `measure` answers "how does this compare to ds4's numbers";
  `served` answers "which of these should I run".

An explicit `--temperature`/`--top-p`/`--min-p`/`--seed`/`--nonce` always
overrides the preset. `--top-p`/`--min-p`/`--seed` are only sent when set — the
default (no `--mode`) is plain temperature-0 with nothing else, matching the
runner's original behaviour.

### Why the nonce is deterministic

Every request carries `SESSION=<token>` ahead of the real system prompt.
llama-server picks a slot by longest-common-prefix similarity against past
requests and restores that slot's KV state; a byte-identical prompt across
cases collides into whatever slot the KV-restore logic picks, which has a
corner case that corrupts generation. A random token avoids the collision but
makes the prompt — and therefore the reasoning path a temperature-0 model
takes — different on every run, so nothing is reproducible.

`--nonce fixed` (the default) is `SESSION=` followed by the first 32 hex
characters of `sha256("<source>/<id>")`: unique per case, so no two cases
collide, and identical across runs, so a run can be repeated byte-for-byte
under `gate`. `--nonce random` is a fresh `uuid4` per request — the same
disruptive behaviour this runner shipped with originally, kept for
comparison.

### One run is not enough for this suite

Same case, same server, same settings, 30 minutes apart: 2265 s and 141,344
characters of reasoning against 321 s and 19,527 characters, both graded
correct. Nothing about the model or the endpoint changed between the two —
the random nonce alone moved a temperature-0 run onto a different reasoning
path. A single `measure` run reports one such path, not the model's accuracy;
run it with several seeds and compare, or use `gate` if the question is
reproducibility rather than variance.

### Think-closure

A case that hits its token ceiling mid-reasoning with no `Answer:` line gets
one follow-up turn: the original exchange, the truncated reasoning (the last
6000 characters, if it ran longer) as an assistant turn, and a request for
exactly one final line, capped at 512 tokens. The case is graded from that
follow-up and marked `forced: true`; the summary's `forced` count says how
many cases needed it. `--no-force` turns this off. `--think-budget N` caps
only the first phase's tokens (default: the resolved `--max-tokens` budget),
so the cost of a wide sweep can be bounded independently of how much room a
model gets before closure kicks in.

### Reasoning budget

`--reasoning-budget N` sends llama-server's `reasoning_budget_tokens` and a
closing message with every case: after N thinking tokens the server injects
the message, closes the thinking block, and the model has to answer. It is the
server's own mechanism, so it works the same way in production
(`--reasoning-budget` on the server). At start the run sends one probe with a
64-token budget and records `reasoning_budget_honoured` — an endpoint that
ignores the field still answers, and would otherwise be measured without a
budget unnoticed. `budget_hit` marks each case that was cut; `budget_hits` in
the summary counts them.

A connection that drops mid-generation is retried twice (`retries` per case,
`retried` in the summary); an HTTP status is not.

### Stalls

Ten minutes of silence on an open stream ends it: the connection is closed,
which cancels the generation, and the case goes to the forced closure with
the reasoning that did arrive. `stalled` marks the case, and the summary
counts them. Seen on GLM-5.3-Flash: the server keeps generating while the
stream carries nothing, and without the cut the case runs to the ceiling and
scores zero after an hour. `--timeout` bounds only the connect and the first
byte.

Two ceilings still bound the first-phase budget: context (`n_ctx` per slot
minus the prompt) and your own `--timeout` (budget ÷ generation speed,
measured at the top — per-token time grows with context). **A run with
`truncated` above 0 is not comparable to one without** — those cases still
had no clean stop even after the forced follow-up.

## Comparing runs

```bash
./compare.py ../../results/glm5.3-flash/measure-seed1 \
             ../../results/glm5.3-flash/measure-seed2 \
             ../../results/glm5.3-flash/measure-seed3
```

Classifies every case common to all the given runs:

- **stable-correct** — correct in every run.
- **stable-incorrect** — wrong in every run.
- **unstable** — correct in some runs and wrong in others. This is the number
  that "one run is not enough" is about.

The table on stdout shows tokens and seconds per run per case; `comparison.json`
holds the same data plus the aggregate: mean score and its spread across runs,
the unstable count, total `forced` and `truncated` cases, and tokens spent per
correct answer (a cost-of-correctness figure, comparable across runs of the
same model).

## Why cases.json is not committed

`cases.json` holds the answer keys. Committing it would put benchmark answers in
a git repository, which is exactly the path by which these suites get
contaminated into a future model's training data. Fetch it instead: the
revision is pinned in `fetch_cases.py`, so runs stay reproducible without the
keys living here.

## How faithful this is to ds4-eval

The prompts, the answer extraction and the matching are ported from
`ds4_eval.c`, so a score here means what a score from `ds4-eval` means. The
port is covered by `test_grade.py`, which asserts the behaviours the C spells
out: `</think>` stripping, last-`Answer:`-wins, prose that must not be read as
a pick ("A careful look", "I'll say C"), negated distractors ("not B, so D"),
leading zeros, `\boxed{}` stripping, aliases, and COMPSEC line-set subsetting.

Two differences remain, both of which make our numbers a **lower bound**
rather than an inflated one:

1. **Think-closure is one-shot, not continuous.** ds4 reserves a reply budget
   and nudges the model toward closing its reasoning as it approaches the
   limit, throughout generation. We speak plain HTTP: a case that hits the
   ceiling gets exactly one forced follow-up (above), not ds4's continuous
   nudging. `--no-force` reproduces ds4's absence of any closure at all.
2. **Reasoning arrives out of band.** llama.cpp returns `reasoning_content`
   separately, so we grade `content` alone. ds4 grades one string and strips
   everything before `</think>`. Same result, different plumbing.

`--mode measure` uses ds4's own temperature/top_p/min_p defaults; the runner's
own default (no `--mode`) is temperature 0, which is not what ds4 samples with.

The default token budget is 16000, matching ds4; hard-suite cases carry their
own per-case budget and override it, which is also ds4's precedence.

## Output

`results.json` holds a summary plus one record per case. The summary records
the run conditions — mode, nonce, temperature/top_p/min_p/seed, max_tokens,
think_budget, whether forcing was enabled, and a `server` snapshot of the
endpoint's `/props` and `/slots` (`build_info`, slot count, `n_ctx` per slot,
the first slot's sampler params) taken once at the start; a field is `null`
if that snapshot call failed, which never aborts the run. Per case: expected,
got, kind, `finish_reason`, `seconds`, `prompt_tokens`/`completion_tokens`
(from the endpoint's `usage`, or a character-based estimate flagged
`estimated: true` when `usage` is missing), `forced`, `repeated_lines` and
`repeated_sentences` in the reasoning, and the full response, so a disputed
grade can be re-read without re-running. `run-config.txt` records the exact
command, the resolved sampling, the pinned cases revision, and the date.
