# BFCL — function calling

The [Berkeley Function-Calling Leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html)
(`bfcl-eval`, pinned in `../provision/setup-eval-server.sh`) asks a model to call
functions and checks the calls against known-good ones: AST matching for single
turns, the resulting state of a simulated backend for multi-turn. No judges.

```bash
export LLAMA_API_KEY=...                       # the endpoint's key; leave unset if it has none
./run.sh <model> <base-url> [api-key-env-name] [--limit N] [--categories LIST] [--mode fc|prompt]
```

The third argument is the **name** of the variable holding the key, never the
key. `./run.sh` with no arguments prints every option.

The wrapper runs on the workstation and the suite on the eval server: it copies
`launch.py`, `remote.sh` and `summarize.py` into a run directory there, starts
them over ssh with the key on stdin, and copies the results back to
`../results/<model>/bfcl-<timestamp>/` (or into the tier directory when
`eval-tier rank` calls it). The run directory is removed after a successful
copy and kept after a failure.

## How bfcl reaches an arbitrary endpoint

bfcl resolves `--model` through a table compiled into the package and rejects a
name it does not know before it sends anything. It has two families of handler
behind that table, and only one of them measures what an agent depends on:

- The handlers for open-weight models (`--skip-server-setup`,
  `REMOTE_OPENAI_BASE_URL`) render the chat template **client-side** from a
  Hugging Face tokenizer and call `/v1/completions`. The server's template and
  its tool-call parser are bypassed, and the model must be one bfcl ships a
  handler for.
- `OpenAICompletionsHandler` calls `/v1/chat/completions` with the functions in
  `tools` and reads the answer from `tool_calls`, taking the endpoint from
  `OPENAI_BASE_URL` and the key from `OPENAI_API_KEY`. That is the path an
  agent uses, so the template and parser are part of what is scored.

`launch.py` registers the model under test in the table with the second
handler — in its own process, nothing in site-packages is edited — and hands
over to bfcl's own CLI. Generation, checking and scoring are upstream's code.

`--mode prompt` registers the same handler in bfcl's prompt mode: functions are
described in the system prompt and the call is parsed from text. A model that
scores well in `prompt` and badly in `fc` has a serving problem (template or
parser), not a capability problem.

## Categories

Default, all checked locally with no external service:

| Category | Cases | What it asks |
|---|---|---|
| `simple_python` | 400 | one function offered, one call |
| `multiple` | 200 | several functions offered, pick one |
| `parallel` | 200 | one function, several calls in one turn |
| `parallel_multiple` | 200 | several functions, several calls in one turn |
| `irrelevance` | 240 | no offered function fits — the right answer is no call |
| `live_simple`, `live_multiple`, `live_parallel`, `live_parallel_multiple` | 258 / 1053 / 16 / 24 | the same four shapes on user-contributed functions and prompts |
| `multi_turn_base` | 200 | a conversation against a stateful simulated backend, scored on the end state |

An agent always has several tools in scope and often issues several calls at
once, so `multiple` and the `parallel*` categories are the core. `irrelevance`
catches the opposite failure, a call invented because tools were on offer. The
`live_*` sets are messier than the synthetic ones and sit lower on the public
board, which is where models still separate. `multi_turn_base` is the only
multi-turn measurement in the `rank` tier that has no second LLM in the loop.

Left out:

| Category | Why |
|---|---|
| `web_search_*` | needs `SERPAPI_API_KEY` |
| `memory_*` | scores a memory backend (KV, vector store, summaries) as much as the model, and the vector variant downloads an embedding model |
| `simple_java`, `simple_javascript` | language-specific type coercion; agents here call JSON tools |
| `live_irrelevance`, `live_relevance` | 884 more abstention cases on top of `irrelevance`, and 16 cases |
| `multi_turn_miss_func`, `multi_turn_miss_param`, `multi_turn_long_context` | three more passes at the cost of the most expensive category; add them with `--categories` |
| `format_sensitivity` | prompt mode only |

## `--limit` and what a number from it is worth

`--limit N` (default 30) runs N cases per category — the ones whose
`sha256(id)` sorts first, so every model gets the same cases and they are not
the head of a file upstream orders by topic. The ids are saved as
`test_case_ids_to_generate.json` with the results. `--limit 0` runs every case.
bfcl cannot aggregate a run of fewer than two cases in total, and the wrapper
refuses one.

At 30 cases a category's standard error is 5–9 pp: enough to see that a model
cannot make parallel calls, not enough to rank two that can. The 280 cases
together carry about 2 pp. In full a category is at 1.5–2 pp, and only a full
category is comparable with the same column on the public board. bfcl's own
composite columns in `score/*.csv` average over every category of the whole
benchmark; for a subset they are not a score, and `summary.json` is per category
for that reason.

The default is sized for the slowest box it has to fit. On `workhorse`
(~60 tok/s, a reasoning model, 2 threads) a single-turn case takes 13 s at the
median and 29 s on average, because the answers that run to the token cap take
132 s each; a `multi_turn_base` case is 10–11 requests and 45–170 s. That puts
the default run near 1.5 hours there, and near 8 on a 22 tok/s box with one
slot. Those figures come from 20 cases.

## Reading a run

```
bfcl-<timestamp>/
  run-config.txt    model, endpoint, options, bfcl-eval version, the exact commands
  summary.json      per category: correct, scored, accuracy, inference errors
  result/           the model's raw answers, with token counts and latency per case
  score/            bfcl's verdicts; every failed case with the reason
  test_case_ids_to_generate.json
  run.log
  CAVEAT            present when the score needs a qualifier
  FAILED            present when the run did not produce a score, with the reason
```

bfcl records a failed request as the model's answer (`Error during inference:
…`) and the checker scores it as wrong, so a dead endpoint or a rejected key
reads exactly like a weak model. `summarize.py` counts those: when every case
is one the run fails with the first error, and when some are it writes
`CAVEAT`. It also counts the cases that spent the whole `--max-tokens` budget —
cut off, usually mid-reasoning, and scored on what was left — and reports the
largest answer per category, so a cap that is too tight shows up as a number
and not as a worse model.

`latency` in `result/` includes time spent queued at the endpoint. On a shared
server it is not a throughput figure.

## Where this departs from upstream's protocol

Three request settings, all in `launch.py`'s `EndpointHandler`, all overridable:

| | upstream | here | why |
|---|---|---|---|
| temperature | 0.001 | not sent; the endpoint's own sampling applies | near-greedy decoding is what reasoning models are documented to loop on, and `rank` asks how the model behaves as served. `--temperature 0.001` restores upstream's. |
| `max_tokens` | not sent | 8192 | bfcl does not stream. The ai-infer boxes put an nginx in front of llama-server that drops a response which has produced no bytes for 300 s, and LiteLLM then sends the request again. Behind that nginx an answer has to arrive inside 300 s to arrive at all: 8192 tokens does at `workhorse`'s ~55 tok/s, and a function call needs about a tenth of it. A slower model behind the same nginx needs a smaller cap. |
| client retries | 2 | 0, with a 1800 s timeout | a retry of a request that ran out of time runs out of time again, and holds a slot while it does. The timeout outlasts the router's own retry so the client never abandons a request the router is still working on. |

Where no such nginx is in the path — `http://host:port` straight to
llama-server, which is also how the router reaches gx10 — the 300 s limit does
not exist, and `--max-tokens` can be raised for a slow box or a model that
reasons at length.

`score/` quotes the expected calls for every failed case. Those are benchmark
answers: think before committing them anywhere public.
