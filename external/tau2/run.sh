#!/usr/bin/env bash
# Run tau2-bench against an OpenAI-compatible endpoint, from the eval server.
#
#   run.sh <model> <base-url> [api-key-env-name] [options]
#
#   <model>             the name the endpoint serves the agent model under
#   <base-url>          with or without /v1
#   [api-key-env-name]  NAME of the environment variable holding the agent
#                       endpoint's key (default LLAMA_API_KEY; unset means no
#                       authentication)
#
#   --domain D            airline (default), retail, telecom
#   --num-tasks N         the domain's first N tasks, 0 for all (default 20)
#   --num-trials N        runs per task; pass^k is reported for k <= N (default 4)
#   --user-model M        the user simulator (default workhorse)
#   --user-base-url U     default https://llm.lwa.dk/v1
#   --user-key-env NAME   NAME of the variable holding the simulator endpoint's
#                         key (default TAU2_USER_API_KEY; when that is unset and
#                         both roles share an endpoint, the agent's key is used)
#   --allow-self-play     run even though agent and simulator are the same model
#   --max-concurrency N   simulations in flight (default 2)
#   --seed N              default 300, upstream's
#   --max-tokens N        per-request cap for both roles, 0 for none (default 8192)
#   --timeout S           seconds LiteLLM waits for one request (default 1800)
#   --agent-llm-args JSON extra LiteLLM arguments for the agent, e.g.
#   --user-llm-args JSON  '{"temperature": 0.0}'; without one the endpoint's
#                         own sampling settings apply
#
# Every option has an environment default (TAU2_DOMAIN, TAU2_NUM_TASKS,
# TAU2_NUM_TRIALS, TAU2_USER_MODEL, TAU2_USER_BASE_URL, TAU2_USER_KEY_ENV,
# TAU2_ALLOW_SELF_PLAY, TAU2_MAX_CONCURRENCY, TAU2_SEED, TAU2_MAX_TOKENS,
# TAU2_REQUEST_TIMEOUT, TAU2_AGENT_LLM_ARGS, TAU2_USER_LLM_ARGS) so a tier run
# can be tuned without editing eval-tier. EVAL_OUT overrides the results
# directory.
#
# See README.md here for the user-simulator choice and what it costs.
set -uo pipefail

SUITE=tau2
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=external/lib/remote.sh
source "$HERE/../lib/remote.sh"

usage() { sed -n '2,35p' "$0" | sed 's/^#\( \|$\)//'; exit 2; }
[[ $# -lt 2 ]] && usage

MODEL="$1"; URL="$(normalize_url "$2")"; shift 2
KEY_ENV=LLAMA_API_KEY
if [[ $# -gt 0 && "$1" != --* ]]; then KEY_ENV="$1"; shift; fi

DOMAIN="${TAU2_DOMAIN:-airline}"
NUM_TASKS="${TAU2_NUM_TASKS:-20}"
NUM_TRIALS="${TAU2_NUM_TRIALS:-4}"
USER_MODEL="${TAU2_USER_MODEL:-workhorse}"
USER_URL="${TAU2_USER_BASE_URL:-https://llm.lwa.dk/v1}"
USER_KEY_ENV="${TAU2_USER_KEY_ENV:-TAU2_USER_API_KEY}"
ALLOW_SELF_PLAY="${TAU2_ALLOW_SELF_PLAY:-}"
CONCURRENCY="${TAU2_MAX_CONCURRENCY:-2}"
SEED="${TAU2_SEED:-300}"
MAX_TOKENS="${TAU2_MAX_TOKENS:-8192}"
TIMEOUT="${TAU2_REQUEST_TIMEOUT:-1800}"
AGENT_EXTRA="${TAU2_AGENT_LLM_ARGS:-{\}}"
USER_EXTRA="${TAU2_USER_LLM_ARGS:-{\}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)          DOMAIN="$2";       shift 2 ;;
    --num-tasks)       NUM_TASKS="$2";    shift 2 ;;
    --num-trials)      NUM_TRIALS="$2";   shift 2 ;;
    --user-model)      USER_MODEL="$2";   shift 2 ;;
    --user-base-url)   USER_URL="$2";     shift 2 ;;
    --user-key-env)    USER_KEY_ENV="$2"; shift 2 ;;
    --allow-self-play) ALLOW_SELF_PLAY=1; shift ;;
    --max-concurrency) CONCURRENCY="$2";  shift 2 ;;
    --seed)            SEED="$2";         shift 2 ;;
    --max-tokens)      MAX_TOKENS="$2";   shift 2 ;;
    --timeout)         TIMEOUT="$2";      shift 2 ;;
    --agent-llm-args)  AGENT_EXTRA="$2";  shift 2 ;;
    --user-llm-args)   USER_EXTRA="$2";   shift 2 ;;
    *) usage ;;
  esac
done
USER_URL="$(normalize_url "$USER_URL")"

STAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_MODEL="${MODEL//\//_}"
OUT="${EVAL_OUT:-$REPO/external/results/$SAFE_MODEL/tau2-$STAMP}"
RUN="$EVAL_ROOT/tau2/runs/$SAFE_MODEL-$STAMP"

[[ "$NUM_TASKS" =~ ^[0-9]+$ ]]        || die "--num-tasks must be a whole number, 0 for all"
[[ "$NUM_TRIALS" =~ ^[1-9][0-9]*$ ]]  || die "--num-trials must be a positive whole number"
[[ "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]] || die "--max-concurrency must be a positive whole number"
[[ "$SEED" =~ ^[0-9]+$ ]]             || die "--seed must be a whole number"
[[ "$MAX_TOKENS" =~ ^[0-9]+$ ]]       || die "--max-tokens must be a whole number, 0 for no cap"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]]     || die "--timeout must be a positive whole number of seconds"
[[ "$NUM_TASKS" == 0 ]] && NUM_TASKS=""

# The same model on both sides of the conversation shares its blind spots with
# its own examiner. The check sees names and URLs only: one model served under
# two names, or behind the router and directly, gets past it.
SELF_PLAY=no
if [[ "$USER_MODEL" == "$MODEL" && "$USER_URL" == "$URL" ]]; then
  [[ -n "$ALLOW_SELF_PLAY" ]] \
    || die "agent and user simulator are the same model ($MODEL at $URL) — pick another --user-model, or pass --allow-self-play and read the score as plumbing, not as a ranking"
  SELF_PLAY=yes
fi

# Checked before anything expands it: bash names the offending string when an
# indirect expansion is given something that is not a name, and a caller who
# passed the key itself would read it back in the error.
[[ "$USER_KEY_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
  || die "--user-key-env must be the NAME of an environment variable holding the key"

KEY="$(key_from "$KEY_ENV" LLAMA_API_KEY)" || exit 1
if [[ -z "${!USER_KEY_ENV:-}" && "$USER_KEY_ENV" == TAU2_USER_API_KEY && "$USER_URL" == "$URL" ]]; then
  USER_KEY="$KEY"; USER_KEY_FROM="$KEY_ENV (shared endpoint)"
else
  [[ -n "${!USER_KEY_ENV:-}" ]] \
    || die "the user simulator's key is not set — export TAU2_USER_API_KEY (or the variable named by --user-key-env) with the key for $USER_URL"
  USER_KEY="${!USER_KEY_ENV}"
  USER_KEY_FROM="$USER_KEY_ENV"
fi

# LiteLLM resolves "os.environ/<NAME>" when it sends the request, so the
# arguments tau2 records in results.json name the variable and not the key. A
# literal api_key in the extra arguments would be recorded verbatim.
#
# max_tokens, timeout and num_retries bound what a reasoning loop can cost.
# Requests are not streamed, and the ai-infer boxes put an nginx in front of
# llama-server that drops a response which has produced no bytes for 300 s;
# LiteLLM then sends it once more, whether or not the caller is still there. So
# behind that nginx the cap has to let an answer arrive inside 300 s, the
# client timeout has to outlast the router's retry, and nothing is retried at
# this level — tau2 retries a failed simulation as a whole.
llm_args() {
  python3 - "$1" "$2" "$3" "$MAX_TOKENS" "$TIMEOUT" <<'PY'
import json, sys
base_url, key_var, extra = sys.argv[1:4]
max_tokens, timeout = int(sys.argv[4]), int(sys.argv[5])
try:
    extra = json.loads(extra)
    assert isinstance(extra, dict)
except (ValueError, AssertionError):
    sys.exit("the LLM arguments must be a JSON object")
if "api_key" in extra or "api_base" in extra:
    sys.exit("api_key and api_base are set by the wrapper; a key given here would be written into results.json")
bounds = {"timeout": timeout, "num_retries": 0}
if max_tokens:
    bounds["max_tokens"] = max_tokens
# A price makes LiteLLM's cost lookup succeed; without one tau2 logs an ERROR
# for every request and the real errors are lost among them.
price = {"input_cost_per_token": 0.0, "output_cost_per_token": 0.0}
print(json.dumps({"api_base": base_url, "api_key": f"os.environ/{key_var}", **bounds, **price, **extra}))
PY
}
AGENT_ARGS="$(llm_args "$URL" TAU2_AGENT_API_KEY "$AGENT_EXTRA")"      || die "bad --agent-llm-args"
USER_ARGS="$(llm_args "$USER_URL" TAU2_USER_API_KEY "$USER_EXTRA")"    || die "bad --user-llm-args"

remote_preflight tau2

mkdir -p "$OUT"
cat > "$OUT/run-config.txt" <<CONFIG
suite:         tau2-bench, text mode, llm_agent vs user_simulator
date:          $(date -Is)
wrapper:       $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown) $(git -C "$REPO" diff --quiet HEAD -- external 2>/dev/null || echo '(external/ modified)')
eval-server:   $EVAL_SERVER
domain:        $DOMAIN
tasks:         ${NUM_TASKS:-all}$([[ -n "$NUM_TASKS" ]] && echo ' (the first N of the base split)')
trials:        $NUM_TRIALS
seed:          $SEED
concurrency:   $CONCURRENCY
max_tokens:    $([[ "$MAX_TOKENS" == 0 ]] && echo "not sent" || echo "$MAX_TOKENS") per request, both roles
timeout:       ${TIMEOUT}s per request, no LiteLLM retries
agent model:   $MODEL
agent url:     $URL
agent key:     from \$$KEY_ENV$([[ "$KEY" == none ]] && echo ' (unset: no authentication)')
agent args:    $AGENT_EXTRA
user model:    $USER_MODEL
user url:      $USER_URL
user key:      from \$$USER_KEY_FROM
user args:     $USER_EXTRA
self-play:     $SELF_PLAY
CONFIG

remote_put "$RUN" "$HERE/summarize.py" "$HERE/remote.sh" "$OUT/run-config.txt"

rc=0
remote_run_with_keys "$RUN" \
  "bash $(remote_quote "$RUN/remote.sh" "$RUN" "$DOMAIN" "openai/$MODEL" "$AGENT_ARGS" "openai/$USER_MODEL" "$USER_ARGS" "$NUM_TASKS" "$NUM_TRIALS" "$CONCURRENCY" "$SEED" "$MAX_TOKENS")" \
  "$KEY" "$USER_KEY" || rc=$?

fetched=0
remote_fetch "$RUN" "$OUT" || fetched=$?
rm -rf "$OUT/summarize.py" "$OUT/remote.sh" "$OUT/data/tau2" "$OUT/pid"
assert_no_key "$OUT" "$KEY" "$USER_KEY"

summary() { python3 -c 'import json,sys; v = json.load(open(sys.argv[1])); [v := v[k] for k in sys.argv[2:]]; print(v)' "$OUT/summary.json" "$@" 2>/dev/null; }

if [[ $rc -eq 0 && $fetched -ne 0 ]]; then
  die "the run finished but its results could not be copied back — they are still at $EVAL_SERVER:$RUN"
fi
if [[ $rc -ne 0 ]]; then
  why="$(last_log_line "$OUT/run.log")"
  die "the run failed on $EVAL_SERVER (exit $rc)${why:+: $why} — log in $OUT/run.log, run directory kept at $RUN"
fi

caveats=()
[[ "$SELF_PLAY" == yes ]] && caveats+=("self-play: $MODEL was its own user simulator")
judged="$(summary simulations_judged)"; expected="$(summary simulations_expected)"
[[ "$judged" == "$expected" ]] || caveats+=("$judged of $expected simulations were judged; the rest never ran")
user_errors="$(summary terminations user_error)"
[[ -n "$user_errors" ]] && caveats+=("$user_errors simulations ended in user_error — the simulator's failure, scored as the agent's")
cut_agent="$(summary truncated_turns agent)"; cut_user="$(summary truncated_turns user)"
[[ "${cut_agent:-0}" == 0 && "${cut_user:-0}" == 0 ]] \
  || caveats+=("${cut_agent:-0} agent turns and ${cut_user:-0} simulator turns spent all $MAX_TOKENS tokens and were cut off")
if [[ ${#caveats[@]} -gt 0 ]]; then
  ( IFS=';'; printf '%s\n' "${caveats[*]}" ) > "$OUT/CAVEAT"
fi

remote "rm -rf $(remote_quote "$RUN")"
printf '\nresults: %s\n' "$OUT"
