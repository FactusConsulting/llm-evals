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
suite that is not wired up yet is not a pass.

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
./run.py --url $HOST --model <alias> --api-key "$KEY" --suite core \
         --max-tokens 98304 --timeout 7200 --out ../results/<model>/ds4-core
```

**Give a reasoning model far more budget than you think, and raise `--timeout`
with it.** The failure is silent: a model that spends the whole budget thinking
writes no `Answer:` line and scores zero, identically to a wrong answer. On the
first GLM-5.3-Flash run at 16000 tokens, **9 of the 10 failures in 41 cases were
this**, each logged on the server as `507521.26 ms / 16000 tokens`. The apparent
54% on GPQA Diamond was the budget, not the model.

Two ceilings bound it: context (`n_ctx` per slot minus the prompt) and your own
timeout (budget ÷ generation speed, measured at the top — per-token time grows
with context). **A run with truncations is not comparable to one without.**

## 5. Write it down

- A `verdict.md` and `judge-summary.md` under the model's results directory: the
  scores, the per-chunk and per-part breakdown, the persistent failure modes, the
  measured throughput, and the run conditions.
- **One row in [DASHBOARD.md](DASHBOARD.md).** That is the only place a number is
  published. Link the evidence.

## 6. Reading the result

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
| tau2 | installed and starts; **no wrapper yet** |
| BFCL | installed and starts; **no wrapper yet** |
| SWE-bench Verified | package installed; needs an agent scaffold |
| Terminal-Bench | not installed |
| Aider polyglot | not installed |

## The eval server

VM 390 at 192.168.2.175, on pve4: 8 cores, 16 GiB, 120 GB on the `ssd` tier,
`x86-64-v3`. Built by `tofu/eval-server` in the homelab repo — see its
`RECREATE.md`, which records the four ways a create can fail on that module.

`external/provision/setup-eval-server.sh` installs the suites, one virtualenv each, and
self-tests by starting every CLI. Two of those failures were not about the box at
all but about undeclared dependencies: bfcl-eval pulls qemu_agent which imports
`soundfile` (needs system libsndfile), and tau2 imports `websockets` through its
voice module without declaring it. Both are handled.

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
