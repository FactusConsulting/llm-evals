# What a "good" task looks like — scope guide for the orchestrator

This is the refinement playbook: how the orchestrator (Claude, human-driven) turns PM's
coarse stories into dev-ready tasks the local fleet models actually deliver. It is also the
design spec for the narrow-delivery eval corpus — a good corpus task and a good real task are
the same shape.

It is distilled from one hard data point (2026-06-22): the fleet Qwen3.6-35B shipped **0 of 6**
broad PRs at ship-quality, but delivered **4/4** atomic tasks **blind** (no answer leaked) while
**self-verifying** — when each task was the right shape. The capability was never the problem.
**Scope + an enforced verification step were.**

## The four properties of a deliverable task

A task is dev-ready only if it has all four. Drop one and you reproduce the broad-PR failures.

1. **Atomic.** One logical change. One PR. One focused session. If "done" needs two unrelated
   changes, two PRs, or two distinct verifications → it is two tasks (or an epic). The broad
   monitoring PR bundled mongo-exporter + meilisearch + VSO-verify and dropped the wiring of
   one of them — three tasks wearing one hat.

2. **Command-checkable acceptance.** "Done" is a single command that exits 0/non-0 — `kustomize
   build`, `go test -race`, `promtool check rules`, `nginx -t`, `helm template`, a query that
   returns the expected row. If acceptance can only be judged subjectively ("looks reasonable"),
   it is NOT dev-ready: either add the check that makes it objective, or it stays an
   orchestrator/human judgment, not a dev task.

3. **An enforced self-verification step.** The task must tell the dev to RUN the acceptance
   command itself and confirm it passes before finishing — not leave it to a reviewer. This is
   the single highest-leverage line. The model self-verifies when asked to (it ran the build,
   saw the error, fixed it, re-ran — in every blind task). The broken PRs skipped exactly this:
   the dev never ran a final `kustomize build`, so "deploys nothing" / "monitoring down" sailed
   through.

4. **Self-contained.** The dev has what it needs in front of it — the file path, the fixture,
   the relevant pattern to mirror ("match how pgvector does it") — without a scavenger hunt
   across the repo. Hunting is where long sessions drift.

## How broad / how narrow — the dial

```
TOO BROAD (epic, not a task)        SWEET SPOT (dev-ready)            TOO NARROW (pointless)
"Add observability for librechat"   "Add a ServiceMonitor for the    "Add the word ServiceMonitor
 → mongo + meili + VSO, 3 checks,    mongodb-exporter Service in       to line 12"
 needs design                       infra/librechat; confirm with     → no judgment, no value;
                                     `kustomize build` that the        the orchestrator should
                                     ServiceMonitor appears"           just do it
```

The sweet spot: **one change, one command proves it, one sitting.** Concretely:
- **≤ 1 PR.** If the diff would span unrelated areas, split.
- **Exactly one acceptance command.** If you need two different checks to call it done, it is
  two tasks.
- **The dev can finish without making a product decision.** Any "should we even…?" or
  "which approach…?" is the orchestrator's call, made BEFORE handing off — bake the decision
  into the constraint, don't ask the dev to make it.

## Constraints: state the footgun, don't make the dev rediscover it

Some correct answers depend on domain knowledge the model may not surface under load (a PDB
with `minAvailable: 1` deadlocks single-replica drains; `kotlin("android")` is not a real
artifact). The orchestrator knows these. **State the constraint** as part of the task —
"the PDB must not block node drains", "use an artifact that actually resolves". This is not
"leaking the answer"; it is the orchestrator doing its job. The blind tasks proved the model
can often get there without it, but stating it removes the variance for free. Rule: if you
know a trap exists, name it; don't gamble that the model rediscovers it under a long context.

## Task template (use this when refining a coarse story)

```
GOAL (one sentence: the outcome)
CONTEXT (the file/dir, the pattern to mirror, why now — self-contained)
CONSTRAINTS (the must-haves + any known footgun named explicitly)
VERIFY (the single command the dev must run and confirm passes before finishing)
```

If you cannot fill in a single VERIFY command, stop — the task is not yet dev-ready; make the
acceptance objective first, or keep it as a judgment task you (the orchestrator) handle.

## The corpus mirrors this

`stories.yaml` (chat) and `exec-tasks/` (blind + self-verify, agentic) are graded on exactly
these properties: obedience (met the constraint), trap-avoidance (dodged the named footgun),
and verification (a command proves it works). A task that can't be graded this way isn't a
good task — for the eval or for the fleet.
