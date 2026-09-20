# tau2-bench — multi-turn tool use against a simulated customer

[tau2-bench](https://github.com/sierra-research/tau2-bench) (pinned by commit in
`../provision/setup-eval-server.sh`, code and task data from the same commit)
puts the model in a customer-service seat: a policy document, a set of tools
over a database, and a customer who wants something. The score is whether the
database ends in the right state and the right things were said. It is graded
deterministically — but the customer is a second LLM.

```bash
export LLAMA_API_KEY=...          # the agent endpoint's key; leave unset if it has none
export TAU2_USER_API_KEY=...      # the fleet key, for the user simulator on the router
./run.sh <model> <base-url> [api-key-env-name] [--num-trials N] [--num-tasks N] [--user-model M]
```

The third argument is the **name** of the variable holding the key, never the
key. `./run.sh` with no arguments prints every option. When agent and simulator
share an endpoint, `TAU2_USER_API_KEY` may be left unset and the agent's key is
used for both.

The wrapper runs on the workstation and the suite on the eval server: it copies
`remote.sh` and `summarize.py` into a run directory there, starts them over ssh
with both keys on stdin, and copies the results back to
`../results/<model>/tau2-<timestamp>/` (or into the tier directory when
`eval-tier rank` calls it). The run directory is removed after a successful
copy and kept after a failure.

Both models are addressed through LiteLLM as `openai/<name>` with `api_base`
set per role, and `api_key` given as `os.environ/<NAME>`, which LiteLLM
resolves when it sends the request. tau2 writes each role's arguments into
`results.json`; this way it writes the variable's name.

## The user simulator

The simulator is part of the instrument. A weak one wanders off its script,
gives up early or invents details, and every such conversation scores 0 **for
the agent**. So its choice moves the score, and a score is only comparable with
another taken with the same simulator.

Upstream's CLI defaults to `gpt-4.1` in both seats; its leaderboard instructions
say any LLM may play the user, that the choice is reported next to the result,
and recommend `gpt-5.2` "for the most accurate results". Neither is available
here: there is no OpenAI key and no Anthropic key.

What the fleet offers is `workhorse`, `experimental` and `bigbrain`.

- **`workhorse` is the default.** It is the one chat model that is always
  served, it has two slots so the simulator does not queue behind itself, its
  128k context holds any conversation, and it changes rarely — which is what
  makes it usable as a fixed instrument. Scores taken with it are comparable
  with each other and **not** with the public leaderboard.
- `experimental` is whatever is being tried that week; an instrument that
  changes under the measurement is not one.
- `bigbrain` is the strongest, but it has one slot and is usually either the
  model under test or busy with a run.

**The same model in both seats is refused.** A simulator shares its blind spots
and its phrasing with itself: it accepts the agent's misreadings of the policy
because it would have made them too. When the model under test *is* `workhorse`,
name another simulator with `--user-model`. `--allow-self-play` overrides the
refusal and marks the run; that is for checking the plumbing, and its score
ranks nothing. The check compares model names and URLs — one model served under
two names, or once behind the router and once directly, gets past it.

Two things keep the simulator's share of the noise visible. `summary.json`
counts how each simulation ended, and `user_error` — the simulator breaking its
own protocol — is called out in `CAVEAT`, because tau2 scores it against the
agent. And the default domain is one where the simulator only talks.

## Domain, tasks, trials

`airline` is the default: 50 tasks, the smallest of the three original
domains, policy-heavy, and historically the one with the lowest scores, so it
has headroom. In `airline` and `retail` the simulated customer only converses.
In `telecom` the customer has tools of its own and must operate them
correctly, which asks more of the simulator than a local model reliably gives;
run it when the simulator is strong. `banking_knowledge` needs a retrieval
backend and is not wired up.

`--num-tasks` takes the first N tasks of the base split — the same N for every
model. The default is 20; `0` runs the domain.

`--num-trials` is how often each task is run. tau2's headline metric is
pass^k, the probability that **all** of k independent attempts at a task
succeed — `C(successes, k) / C(trials, k)`, averaged over tasks — and it is
reported for every k up to the number of trials. pass^1 is the mean; the fall
from pass^1 to pass^4 is how much of the score was luck. The default is 4, the
number upstream asks for.

The defaults are 80 simulations. That resolves a model that mostly fails from
one that mostly succeeds. It does not separate two models a few points apart:
the standard error on pass^1 is around 5 pp, more with the correlation within
a task. Run the whole domain before deciding between close candidates.

With `workhorse` in both seats the first two `airline` tasks took 55 s and 90 s:
5–11 agent turns at 1 800–4 500 generated tokens, 3–6 simulator turns at
700–1 000. Those two are short tasks; budget a few minutes per simulation, and
the agent's generation speed sets the pace.

## Sampling

No sampling parameters are sent unless `--agent-llm-args` / `--user-llm-args`
name them, so each endpoint's own settings apply — the recipe its model profile
carries. tau2's CLI default is `{"temperature": 0.0}` for both roles. That is
left out on purpose: the `rank` tier asks how the model behaves as it is
served, greedy decoding is what reasoning models are documented to loop on, and
on a local server temperature 0 makes the trials near-copies of each other,
which turns pass^k into pass^1 written four times. tau2 seeds each trial
(`--seed` derives them), and llama-server honours the seed.
`--agent-llm-args '{"temperature": 0.0}'` restores upstream's setting.

## Bounds on a request

Every request from either role carries `max_tokens` 8192, a 1800 s timeout and
no LiteLLM retries (`--max-tokens`, `--timeout`). tau2 does not stream, the
ai-infer boxes put an nginx in front of llama-server that drops a response
which has produced no bytes for 300 s, and LiteLLM then sends it again — so
behind that nginx an answer has to arrive inside 300 s to arrive at all, and a
reasoning loop without a cap holds a slot until something upstream gives up.
8192 tokens arrives in time at `workhorse`'s ~55 tok/s; a turn needs a fraction
of it, and a slower model behind the same nginx needs a smaller cap. Turns that
spent all of it are counted per role in `summary.json` and named in `CAVEAT`. A
simulation whose request failed is retried as a whole by tau2 (`--max-retries`,
3 by default).

Where no such nginx is in the path — straight to llama-server, which is also
how the router reaches gx10 — the 300 s limit does not exist, and the cap can
be raised for a slow box.

## Reading a run

```
tau2-<timestamp>/
  run-config.txt    both models, both endpoints, options, tau2 commit, the exact command
  summary.json      avg reward, pass^k, simulations judged vs expected, how they ended, cut-off turns
  data/simulations/results/results.json    every conversation, tool call and verdict
  run.log
  CAVEAT            present when the score needs a qualifier
  FAILED            present when the run did not produce a score, with the reason
```

tau2 drops simulations that ended in `infrastructure_error` from its averages
with a log line, so an endpoint that dies halfway shrinks the denominator
instead of failing the run. `summary.json` reports judged against expected
simulations, a shortfall goes into `CAVEAT`, and a run where nothing was judged
fails.

`--max-concurrency` (default 2) is the number of conversations in flight. Each
holds one request at a time, against the agent or the simulator; keep it at or
under the slots of the smaller endpoint.

`results.json` contains the tasks with their evaluation criteria. Those are
benchmark answers: think before committing them anywhere public.
