# Runbook — how to test a model

Pointing a new model at this repo: work top to bottom. Every step says what to
check before moving on, because each one has a way of looking fine while being
wrong.

## 0. Pre-flight — record what you are measuring

A score without these four facts cannot be compared to anything later.

```bash
HOST=http://192.168.2.173:30000        # the endpoint under test
KEY=none                                # or the fleet key for llm.lwa.dk

curl -sS -H "Authorization: Bearer $KEY" $HOST/v1/models | jq -r '.data[].id'
curl -sS -H "Authorization: Bearer $KEY" $HOST/props | python3 -c "
import json,sys,hashlib
r=json.load(sys.stdin)
print('build_info:   ', r['build_info'])
print('template_sha: ', hashlib.sha256(r['chat_template'].encode()).hexdigest()[:16])
print('n_ctx/slot:   ', r['default_generation_settings']['n_ctx'])
print('model_path:   ', r.get('model_path','?'))"
```

Then one live request, and check whether `reasoning_content` is in the reply. A
thinking model changes the token budgets in every step below.

**Confirm the box is yours.** `curl -s $HOST/slots` — concurrent traffic does not
corrupt a score but it stretches a run several-fold and muddies any timing you
record. One run in this repo took 77 minutes on a chunk that takes 19.

## 1. Pick the tier

| Tier | Run it when | What it answers |
|---|---|---|
| `gate` | a build, quant or serving config changed | did anything break |
| `rank` | deciding whether a model joins the fleet | is it better than what we run |
| `deep` | choosing the fleet's primary model | can it do the actual work |

```bash
external/bin/eval-tier gate <model-name> $HOST [$KEY]
```

The driver writes `external/results/<model>/<tier>-<timestamp>/STATUS`, naming
every suite that ran **and every suite it skipped, with the reason**. Read it. A
suite that is not wired up yet is not a pass, and a suite that ran with a
qualifier says so on its line.

`rank` reaches the eval server over ssh, and tau2 needs a second model to play
the customer. Unless the model under test sits behind the router itself, export
the fleet key for that simulator first:

```bash
export LLAMA_API_KEY=...                # the endpoint under test; unset if it has none
export TAU2_USER_API_KEY=...            # the key for https://llm.lwa.dk/v1
external/bin/eval-tier rank <model-name> $HOST
```

## 2. The knowledge suite — one run

```bash
MODEL_DIR=results/<descriptive-name>
mkdir -p $MODEL_DIR/run1
ln -s ../gemma4-26b-q6k/chunks $MODEL_DIR/chunks      # the shared question set

for i in $(seq 1 9); do
  ./run-chunk-validated.sh $MODEL_DIR/chunks/chunk$i-*.txt \
    $MODEL_DIR/run1/chunk$i-response.txt "$HOST/v1/chat/completions" "$KEY" "<alias>"
done
```

**One run is the routine.** Three are for a new baseline — a new model, a new
architecture, a new quant family — because the run-to-run range is itself a
signal: Gemma 4 4B E4B scored 96.67% with a 1.62 pp range, and one run would have
shown 96.67% and hidden that it was unstable.

Before judging, check every response file is non-empty and none ends mid-sentence.
A truncated answer scores zero and looks exactly like a wrong one.

Then judge: two independent Opus judges per run, `mean(A, B)` per question. The
procedure is [skills/judge-llm-eval/HOW-TO-DRIVE-EVAL.md](skills/judge-llm-eval/HOW-TO-DRIVE-EVAL.md).
Run the deterministic Part B validator too, and treat a disagreement with the
judges as a question, not as noise:

```bash
python3 skills/judge-llm-eval/validators/validate-part-b.py $MODEL_DIR/run1/chunk9-response.txt
```

## 3. Loop detection — one pass

```bash
cd loop-detection
./run-eval.sh --model-url $HOST --model-name <model-name> --api-key "$KEY" --delay-between 5
```

Twelve scenarios. Read the flags rather than counting them: LD11 asks for a
cumulative table across five batches, so its paragraphs **must** repeat and it
flags every time on a model that is doing it right. An `EMPTY_RESPONSE` flag is
the real failure — it means the model spent its whole budget and said nothing.

## 4. ds4-eval — deterministic, no judges

```bash
cd external/ds4-eval
./fetch_cases.py                       # pinned revision; the keys are not committed
./run.py --url $HOST --model <alias> --api-key "$KEY" --suite core --mode gate \
         --max-tokens 98304 --timeout 7200 --out ../results/<model>/ds4-core-gate
```

**Give a reasoning model far more budget than you think, and raise `--timeout`
with it.** The failure is silent: a model that spends the whole budget thinking
writes no `Answer:` line and scores zero, identically to a wrong answer. A
case that hits the ceiling with no `Answer:` line gets one forced follow-up
turn asking for exactly one final line (see README.md); `truncated` in the
summary counts cases where even that did not produce a clean stop.

**On llama-server, also pass `--reasoning-budget 65536`.** The server cuts the
thinking there, injects a closing message, and the model answers from what it
has — so a runaway generation ends in an answer instead of a blank. The run
probes at start that the endpoint enforces it (`reasoning_budget_honoured` in
the summary); `budget_hit` marks the cases it cut. The forced follow-up turn
does not rescue those cases: a model at maximum reasoning effort starts thinking
again and runs out of its 512 tokens.

Two ceilings still bound the budget: context (`n_ctx` per slot minus the
prompt) and your own timeout (budget ÷ generation speed, measured at the top —
per-token time grows with context).

**`--mode gate` vs `--mode measure`.** Both use a nonce fixed per case
(`sha256(source/id)`, not a random `uuid4`) so the same case sends the same
system prompt on every run — otherwise llama-server's KV-restore-by-prefix
logic collides cases into each other's slots. `gate` is temperature 0 and
seed 0: same build, same cases, same transcripts, so a difference between two
gate runs means the build changed something. `measure` is ds4's own sampling
(temperature 1.0, top_p 1.0, min_p 0.05) with the seed from `--seed`; call it
once per seed and compare.

**One `measure` run is not enough.** Same case, same server, same settings, 30
minutes apart: 2265 s / 141,344 characters of reasoning against 321 s /
19,527 characters, both graded correct — the random nonce this runner used to
carry moved a temperature-0 run onto a different reasoning path with nothing
else changed. Run several seeds and feed the run directories to `compare.py`:

```bash
./compare.py ../results/<model>/measure-seed1 ../results/<model>/measure-seed2 ...
```

Per case, it prints stable-correct / stable-incorrect / unstable across the
given runs; `unstable` is the count that matters. `comparison.json` adds the
aggregate: mean score and its spread across runs, forced/truncated totals, and
tokens spent per correct answer.

## 5. tau2 and BFCL — the rank suites

Both run on the eval server; the wrappers drive them from here and bring the
results back. The third argument is the **name** of the environment variable
holding the key — a key never goes on a command line.

```bash
export LLAMA_API_KEY=...                 # the endpoint under test; unset if it has none
export TAU2_USER_API_KEY=...             # the fleet key, for tau2's user simulator

external/bfcl/run.sh <model-name> $HOST
external/tau2/run.sh <model-name> $HOST --num-trials 4
```

**BFCL** scores function calls against known-good ones, through
`/v1/chat/completions` with native `tools` — so the server's chat template and
tool-call parser are scored with the model. It runs 30 hash-selected cases from
each of ten categories by default; `--limit 0` runs them whole. Which categories
and why: [external/bfcl/README.md](external/bfcl/README.md).

**tau2** is a conversation between the model and a simulated customer, and the
customer is a second LLM. That simulator is part of the instrument: the default
is `workhorse`, a run is only comparable with runs that used the same one, and
the wrapper **refuses** to let a model be its own customer. Read
[external/tau2/README.md](external/tau2/README.md) before quoting a tau2 number.

Each results directory has a `summary.json`, a `run-config.txt` with the exact
command and pinned version, and — when they apply — a `CAVEAT` or a `FAILED`
file. Both suites have a way of turning an unreachable endpoint into a low
score instead of an error; the summaries count those cases so it cannot pass
unnoticed.

## 6. Write it down

- A `verdict.md` and `judge-summary.md` under the model's results directory: the
  scores, the per-chunk and per-part breakdown, the persistent failure modes, the
  measured throughput, and the run conditions.
- **One row in [DASHBOARD.md](DASHBOARD.md).** That is the only place a number is
  published. Link the evidence.

## 7. Reading the result

Per sub-scale, never as one number. The GLM-5.3-Flash run scored 98.69% overall
while chunk 9 Part B — code that has to run — was 73.3%; the single figure hides
the only part that still discriminates.

A delta under 1 pp on the knowledge suite is noise. If two models are inside that,
the suite has told you they both clear the bar and nothing more — take the ranking
question to `rank`.


## What each tier costs

| Tier | Suites | Rough cost |
|---|---|---|
| `gate` | ds4-eval `core`, loop detection, our knowledge suite (1 run) | 2-4 h |
| `rank` | ds4-eval `hard`, tau2, BFCL | ~1 day |
| `deep` | SWE-bench Verified subset, Terminal-Bench | days |

For a thinking model, add `--max-tokens 16000` to the ds4-eval runs: the hard
suite's per-case budget is 4096 and a reasoning model spends it all before
answering, which scores zero. The runner warns when it happens.

Results land in `external/results/<model>/<tier>-<timestamp>/`, with a `STATUS`
file naming every suite that ran and every suite that was skipped and why. A
skipped suite is never silent: silence would read exactly like a pass.

## Why the tiers are split this way

Our own knowledge suite is **saturated at the top**. Gemma 4 26B (98.56%), GLM-5.3-Flash
(98.69%) and Gemma 4 31B (98.92%) sit within 0.36 pp of each other and our measurement
precision is 0.13 pp, so it cannot rank them — the spread is the noise floor. It is
still the right gate: it is precise, and precision is what catches "did this build break
something". Hermes 4 14B scored 92.75% on it, so the bar is not automatic. The long
version, including what the residual failures are, is in
[`../METHODOLOGY.md`](../METHODOLOGY.md#the-suite-is-saturated-at-the-top).

One run, not three, from here on. Three runs bought 0.13 pp of precision on a
saturated measure for seven hours and six judges. **Keep three runs when
establishing a new baseline** — a new model, a new architecture, a new quant
family — because the run-to-run range is itself a signal: Gemma 4 4B E4B scored
96.67% with a 1.62 pp range, and a single run would have shown 96.67% and hidden
that it was unstable.

The other suites are not saturated, and they are graded deterministically, so
they cost no judge tokens and carry no judge noise.

## Suite status

Read this before trusting a number.

| Suite | State |
|---|---|
| ds4-eval `core` (92 cases: 25 GPQA Diamond, 25 SuperGPQA, 25 AIME 2025, 17 defensive code review) | **works**; smoke-tested against gx10 |
| ds4-eval `hard` (50 cases: 30 MMLU-Pro, 10 OlympiadBench, 5 LiveBench, 5 NIST Juliet) | **works**; deterministic, no judges — see `external/ds4-eval/README.md` |
| loop detection | works (ours) |
| own knowledge suite | works, but driven by hand — see `../skills/judge-llm-eval/HOW-TO-DRIVE-EVAL.md`; the tier driver only prints a reminder |
| BFCL | **works** end to end through `external/bfcl/run.sh`; smoke-tested against `workhorse` on the router with 2 cases in each of the ten default categories (`fc`) and 2 cases in `prompt` mode. No run at the default size or in full exists yet |
| tau2 | **works** end to end through `external/tau2/run.sh`; smoke-tested on 2 `airline` tasks with `workhorse` in both seats, which checks the plumbing and ranks nothing. No run with a separate user simulator exists yet, and `retail` and `telecom` have not been run |
| `eval-tier rank` | the tau2 and BFCL stages are tested through the driver, including a refusal and a failed run reaching `STATUS` with their reasons; the tier has not been run as a whole (ds4-eval `hard` first, then both) |
| SWE-bench Verified | package installed; needs an agent scaffold |
| Terminal-Bench | not installed |
| Aider polyglot | not installed |

## The eval server

VM 390 at 192.168.2.175, on pve4: 8 cores, 16 GiB, 120 GB on the `ssd` tier,
`x86-64-v3`. Built by `tofu/eval-server` in the homelab repo — see its
`RECREATE.md`, which records the four ways a create can fail on that module.

`external/provision/setup-eval-server.sh` installs the suites, one virtualenv each,
pinned — bfcl-eval by version, tau2 by commit — and self-tests by starting every
CLI. Two of those failures were not about the box at all but about undeclared
dependencies: bfcl-eval pulls qemu_agent which imports `soundfile` (needs system
libsndfile), and tau2 imports `websockets` through its voice module without
declaring it. Both are handled.

tau2's wheel carries code only. Its tasks, policies and databases come from a
sparse checkout of the same commit under `/opt/evals/tau2/src`, and the
self-test loads a domain from it: `tau2 --help` starts fine without any tasks
to run.

The box was originally left on Proxmox's `kvm64` CPU default, which exposes only
the x86-64 baseline. NumPy's wheels need x86-64-v2, so every scientific package
died at import and tau2, BFCL, SWE-bench and Terminal-Bench were blocked
together. That is why the stack now declares `x86-64-v3` explicitly, and why the
provisioner checks for `avx2` before it trusts anything.

## Capacity

The VM is 8 cores, 16 GiB RAM, 120 GB disk. The three suite environments take
about 8 GB — BFCL alone is 5.9 GB because it pulls torch — leaving ~105 GB for
container images.

SWE-bench Verified builds or pulls one image per instance, and the full image set
is larger than that. Run a **fixed, seeded subset** — 50 instances is enough to
compare models — and check `df -h /opt/evals` before and after. The full 500 is a
one-off for a number you want to quote outside the house.

Throughput is the other ceiling: gx10 generates at ~22 tok/s. At ten minutes per
SWE-bench instance, 500 instances is 83 hours.

## Contamination

GPQA Diamond, SWE-bench and MMLU-Pro are all in recent training sets to some
degree. That does not matter for the use these suites are best at here —
comparing **the same model at two quants**, where both sides are equally
contaminated. It does make absolute numbers across model families unreliable, so
do not quote them as if they were leaderboard scores.
