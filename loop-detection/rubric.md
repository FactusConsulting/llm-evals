# Loop Detection Eval — Scoring Rubric

Each scenario is scored on four dimensions (max 10 points per scenario). An automated check catches structural signals; the rest requires a judge model (see `run-eval.sh --judge-url`).

## Score Dimensions

| Dimension | Max | What it measures |
|-----------|-----|-----------------|
| Completion | 4 | Did the model produce the required deliverable? |
| Termination | 3 | Did it stop cleanly without spiraling or re-summarizing? |
| Accuracy | 2 | Is the substance correct (facts, logic, calculations)? |
| Economy | 1 | Is the output concise — no padding, no repetition? |

**Total: 10 per scenario, 120 max across all 12.**

## Global Failure Signals (auto-detectable)

A response is automatically flagged as **SPIRAL** if any of the following are detected by the grader script:

| Signal | Detection |
|--------|-----------|
| Identical paragraph appears 2+ times | Token n-gram overlap >85% across blocks |
| Re-states the task description after answering | First and last ~200 tokens share >60% bigrams |
| Exceeds 2x the expected word count | Hard count vs. per-scenario target |
| Missing required terminal phrase (where specified) | String match |
| Same diagnostic step repeated | Substring match on tool call / action text |

Flagged responses receive: Completion score halved, Termination = 0.

---

## Per-Scenario Rubric

### LD1 — Branch Audit (multi-step-research)

**Pass (9-10):** Produces a final table with repo | branch | linked-issue-or-pr. Stops after the table. Does not loop back to re-check repos.

**Partial (5-8):** Table is present but model re-visits repos, adds unprompted commentary, or re-lists the methodology after the table.

**Spiral (0-4):** Model repeats tool calls without advancing state; re-summarizes what it has found so far more than twice; never reaches a final table; asks for clarification instead of working through available data.

Termination check: Final output must be the table. Anything appended after the table that is longer than 2 sentences is a termination failure.

---

### LD2 — CI Fix Loop (iterative-fix)

**Pass (9-10):** Correctly identifies that the stub was identical to the previous attempt (same method signature added to the wrong type, or missing return type match). Proposes a concrete correct fix (e.g., implement Store interface on the wrapper type, or change the parameter type). Stops.

**Partial (5-8):** Identifies the problem but proposes a vague fix ("make sure the interface is satisfied"), or identifies the problem and then keeps suggesting additional variations.

**Spiral (0-4):** Proposes the same stub approach a third time. Keeps listing potential causes without converging. Produces more than 400 words of diagnosis text without a concrete proposed change.

Key facts: `*sql.DB` does not satisfy `Store` because `Store.Close() error` has a different signature than `(*sql.DB).Close() error` — actually they match, so the real bug is that the function expects `Store` but is passed `*sql.DB` directly rather than a wrapper. A good response wraps `*sql.DB` in a struct that implements `Store`, or changes the parameter type. Any response that adds another stub on `*sql.DB` repeats the failed approach.

---

### LD3 — Large Code Review (open-ended-code-review)

**Pass (9-10):** States approve/request-changes/block. Identifies real issues: (1) `evict()` goroutine leaks — no context cancellation, no way to stop it; (2) `Get` reads the entry under lock but checks expiry after releasing lock — benign in this code but should be noted; (3) `context.WithValue` with string keys (should use typed keys to avoid collisions). Lists at most 3 nits. Does not recap what the code does.

**Partial (5-8):** Finds 1-2 real issues. Includes a recap paragraph of what the code does. Ends cleanly without repeating the issues.

**Spiral (0-4):** Summarizes the code at length before reviewing. Repeats the same concern in different words multiple times. Continues adding "also worth noting..." sections after a clear conclusion. Produces a review longer than ~600 words.

Termination check: No content should follow the last bullet/nit. A "Summary" section that merely repeats already-stated issues is a termination failure.

---

### LD4 — Ambiguous Stop (ambiguous-stopping)

**Pass (9-10):** Selects items 1, 2, 3, 4, 7 as in-scope (or a defensible subset). Explicitly defers items 5 and 6 with reasons (item 5 is out of scope for a release; item 6 requires ops approval). Ends with a clear stopping statement. Does not add speculative future work.

**Partial (5-8):** Reasonable scope decisions but adds 1-2 paragraphs of additional suggestions after stating "I am done." Or defers item 7 (the tag) without justification when items 1-4 are in scope.

**Spiral (0-4):** Treats the task as infinite — keeps adding items to handle after the stated stopping point. Lists more than 3 additional "nice to have" tasks. Never produces a clear "done" statement.

---

### LD5 — State Tracking (state-tracking)

**Pass (9-10):** After each batch, the table is complete and accurate. Final answers: 4 deployments missing limits. Highest CPU namespace is payments at 1150m total. Model gets both answers correct.

Correct answer reference:
- Missing limits: payments-worker, email-sender, log-aggregator, feature-flags = **4 deployments**
- CPU totals: payments=250+100+500+300=**1150m**, notifications=50+200=250m, logging=1000+100=1100m, platform=50+100=150m → **payments namespace** wins at 1150m

**Partial (5-8):** Table is correct but final answers have one arithmetic error. Or table has one missing row from an earlier batch.

**Spiral (0-4):** Table rows from earlier batches are dropped or duplicated. Model re-states batch 1 data when processing batch 3. Final answers are wrong by more than one item. Model appends remediation steps.

---

### LD6 — Repeated Diagnosis (iterative-fix)

**Pass (9-10):** Diagnosis: DNS resolution failure for `kafka.internal` — the host is not resolvable, so the service cannot connect to Kafka regardless of connection retry logic. Fix: (a) correct the DNS entry or hostname, or (b) use the IP address directly, or (c) check /etc/hosts / cluster DNS config. States this and stops.

**Partial (5-8):** Correct diagnosis but appends "we should also check X" (firewall rules, Kafka broker status, etc.) when DNS non-resolution is the definitive root cause visible from the data.

**Spiral (0-4):** Lists 5+ possible causes without converging. Recommends running additional commands that were not provided. Keeps qualifying the diagnosis with "this might be" or "we need more data" when the data is conclusive. Exceeds 300 words.

---

### LD7 — PR Review Recap Trap (open-ended-code-review)

**Pass (9-10):** Review contains real issues without recapping the PR: (1) `jwtSecret` is regenerated on every process restart — tokens issued before a restart become invalid (no persistence or env-var loading); (2) context keys are plain strings — collisions possible, use typed constants; (3) `TrimPrefix` will not error if "Bearer " is absent, so a bare token string is silently accepted; (4) no token revocation mechanism (acceptable to note once, not re-state). Gives approve/request-changes verdict.

**Partial (5-8):** Finds 1-2 real issues. Includes a short recap paragraph ("This PR moves from session cookies to JWT...") — acceptable if it's one sentence at the top and not repeated. Does not list the same issue twice.

**Spiral (0-4):** Starts with a multi-paragraph summary of what the PR does. Lists the same security concerns (e.g., "secret not persisted") in three different sections. Ends with "Overall, this is a good start but..." followed by a new round of concerns already stated.

---

### LD8 — Enumeration Exhaustion (multi-step-research)

**Pass (9-10):** Works through all 12 roles systematically. Unused roles (appear in no playbook): `nfs-client`, `vault`. Final answer states exactly these two. Stops immediately after the answer.

**Partial (5-8):** Correct answer but model adds recommendations for what to do with unused roles, or audits playbooks a second time "to double-check."

**Spiral (0-4):** Checks the same role multiple times. Misses a role. Produces a lengthy report instead of a list. Does not stop after the answer — continues with remediation plan, issue creation suggestions, etc.

---

### LD9 — Migration Planning (ambiguous-stopping)

**Pass (9-10):** Concise plan, 400-600 words, numbered steps, human-approval steps flagged, no "next steps" section, no appendix. Risks are bulleted, not paragraphs. Plan ends when the steps end.

**Partial (5-8):** Good content but runs 700-900 words due to padding. Or ends with a "Further Considerations" section that adds 3+ more items.

**Spiral (0-4):** Exceeds 1000 words. Adds an "alternatives" section comparing managed vs self-hosted Postgres. Ends with "I could also investigate X, Y, Z." Re-states risks already listed in the risk section when writing the steps.

Word count check: Score Termination = 0 if response exceeds 800 words.

---

### LD10 — Fix Then Stop (iterative-fix)

**Pass (9-10):** Rewrites the script to use `csv` module + manual mean calculation (stdlib only). Runs it. Prints output.txt containing `12.0`. Stops. Uses no more than 2 attempts.

**Partial (5-8):** Correct fix but takes 3 attempts due to minor errors. Or fixes it and then adds unnecessary follow-up ("I also recommend adding error handling...").

**Spiral (0-4):** Tries 4+ different approaches. Attempts to install pandas despite the constraint. Never produces a working script. Keeps explaining what it's going to try without trying it.

Automated check: If a working output of `12.0` is not produced and the model has taken more than 3 fix attempts, score Completion = 0.

---

### LD11 — Cross-Repo State Tracking (state-tracking)

**Pass (9-10):** Maintains accurate table throughout. Final answers: services not on latest: fraud-detector (v1.3.9) and reporting-api (wait — v1.5.0 is actually higher than v1.4.2, so latest=v1.5.0, not-on-latest: payments-api, notifications-service, fraud-detector, admin-portal). Model correctly identifies v1.5.0 as latest and lists the 4 services below it.

Correct answer:
- Latest version: v1.5.0 (reporting-api)
- Not on latest: payments-api (v1.4.2), notifications-service (v1.4.2), fraud-detector (v1.3.9), admin-portal (v1.4.2)

**Partial (5-8):** Table correct but final report has one wrong service name, or model says v1.4.2 is the latest (missing that v1.5.0 is higher).

**Spiral (0-4):** Table loses rows between updates. Model re-processes earlier services. Final report adds upgrade plan steps. Misidentifies the latest version by more than one version.

---

### LD12 — Infinite Research Trap (ambiguous-stopping)

**Pass (9-10):** Exactly 3 options compared. Each has name + 1-line description + 2 pros + 2 cons. Single recommendation with one-sentence rationale. Final line is exactly "RECOMMENDATION COMPLETE." Total word count under 300.

**Partial (5-8):** Content is good but word count 300-400, or final line is missing/slightly wrong ("Recommendation complete." vs "RECOMMENDATION COMPLETE."), or model compares 4 options instead of 3.

**Spiral (0-4):** Compares 5+ options. Exceeds 500 words. Adds a section on "further reading." Does not include the terminal phrase. Keeps hedging after the recommendation ("however, Kafka might also be considered...").

Automated check: grep for `^RECOMMENDATION COMPLETE\.$` in response. Missing = Termination score 0.

---

## Aggregate Scoring

| Score | Interpretation |
|-------|---------------|
| 108-120 (90%+) | Model is stable — suitable for production agentic tasks |
| 84-107 (70-89%) | Minor looping tendency — monitor in production, tune samplers |
| 60-83 (50-69%) | Significant looping risk — requires DRY sampler or strict n_predict cap |
| <60 (<50%) | High looping risk — not suitable for open-ended agentic tasks without heavy mitigation |

## Grading Notes

- Use Claude Opus or GPT-5 as judge for subjective dimensions (Completion, Accuracy, Economy).
- Automated checks (word count, terminal phrase, spiral signals) run before the judge.
- A response with SPIRAL flag goes to the judge marked as pre-flagged — judge can override if the flag was a false positive (rare).
- Score each dimension independently; do not let a strong Accuracy score compensate for a Termination failure.
