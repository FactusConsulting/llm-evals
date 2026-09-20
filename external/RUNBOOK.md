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

Our own knowledge suite is **saturated at the top**. Gemma 4 26B, Gemma 4 31B and
GLM-5.3-Flash sit within 0.36 pp of each other and our measurement precision is
0.13 pp, so it cannot rank them — the spread is the noise floor. It is still the
right gate: it is precise, and precision is what catches "did this build break
something". Hermes 4 14B scored 92.75% on it, so the bar is not automatic.

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
| ds4-eval `core` / `hard` | **works**; smoke-tested against gx10 |
| loop detection | works (ours) |
| own knowledge suite | works, but driven by hand — see `HOW-TO-DRIVE-EVAL.md`; the tier driver only prints a reminder |
| tau2 | installed on the eval server; **blocked**, and no wrapper yet |
| BFCL | installed on the eval server; **blocked**, and no wrapper yet |
| SWE-bench Verified | package installed; needs an agent scaffold and more disk than the VM has |
| Terminal-Bench | not installed |

## The blocker

The eval server (VM 390, 192.168.2.175, on pve7) runs with Proxmox's default
`kvm64` CPU model, which exposes only the x86-64 baseline. NumPy's wheels require
x86-64-v2, so every scientific Python package dies at import:

```
RuntimeError: NumPy was built with baseline optimizations:
(X86_V2) but your machine doesn't support: (X86_V2).
```

That takes out tau2, BFCL, SWE-bench and Terminal-Bench together. The host is a
Xeon W-2145, so there is plenty to expose. Fix it on the Proxmox node:

```bash
ssh root@pve7.lwa.dk 'qm set 390 --cpu host && qm stop 390 && qm start 390'
```

A CPU type change needs a full power cycle, not a reboot from inside the guest.
Verify with `grep -w sse4_2 /proc/cpuinfo` on the guest, then re-run
`provision/setup-eval-server.sh`, whose self-test starts each CLI.

`tofu/eval-server` in the homelab repo declares `vm_cpu_type = "host"` already —
the module default is correct. The running guest never got it because that module
has no state, so nothing ever reconciled the two. The same gap had the guest on
pve7 while the code said pve4; the code now says pve7.

## Capacity

The VM is 4 cores, 4 GB RAM, 30 GB disk. After the three suite environments there
are ~13 GB free, and BFCL alone is 5.9 GB because it pulls torch.

SWE-bench Verified builds or pulls one image per instance and the full image set
is far larger than this disk. Run a **fixed, seeded subset** — 50 instances is
enough to compare models — and check `df -h /opt/evals` before and after. The
full 500 is a one-off for a number you want to quote outside the house, and it
needs more disk than this guest has.

Throughput is the other ceiling: gx10 generates at ~22 tok/s. At ten minutes per
SWE-bench instance, 500 instances is 83 hours.

## Contamination

GPQA Diamond, SWE-bench and MMLU-Pro are all in recent training sets to some
degree. That does not matter for the use these suites are best at here —
comparing **the same model at two quants**, where both sides are equally
contaminated. It does make absolute numbers across model families unreliable, so
do not quote them as if they were leaderboard scores.
