# Benchmark runbook

Three tiers, because running everything on every model costs days. Pick the tier
by the decision you are making, not by how thorough you feel.

| Tier | Run it when | Suites | Rough cost |
|---|---|---|---|
| `gate` | a build, quant or serving config changed | ds4-eval `core`, loop detection, our knowledge suite (1 run) | 2-4 h |
| `rank` | deciding whether a model joins the fleet | ds4-eval `hard`, tau2, BFCL | ~1 day |
| `deep` | choosing the fleet's primary model | SWE-bench Verified subset, Terminal-Bench | days |

```bash
external/bin/eval-tier gate glm5.3-flash http://192.168.2.173:30000
```

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
| ds4-eval `hard` (50 cases: 30 MMLU-Pro, 10 OlympiadBench, 5 LiveBench, 5 NIST Juliet) | **works**; deterministic, no judges — see `ds4-eval/README.md` |
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

`provision/setup-eval-server.sh` installs the suites, one virtualenv each, and
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
