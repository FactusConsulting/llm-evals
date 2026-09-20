#!/usr/bin/env bash
# Run BFCL against an OpenAI-compatible endpoint, from the eval server.
#
#   run.sh <model> <base-url> [api-key-env-name] [options]
#
#   <model>             the name the endpoint serves the model under
#   <base-url>          with or without /v1
#   [api-key-env-name]  NAME of the environment variable holding the key
#                       (default LLAMA_API_KEY; unset means no authentication)
#
#   --categories LIST   comma-separated bfcl categories or groups
#   --limit N           cases per category, 0 for every case (default 30)
#   --threads N         concurrent requests; keep it at or under the slots the
#                       endpoint serves (default 2)
#   --temperature T     sent with every request; by default none is sent and the
#                       endpoint's own sampling applies (upstream sends 0.001)
#   --max-tokens N      per-request cap, 0 for none (default 8192)
#   --timeout S         seconds the client waits for one request (default 1800)
#   --mode fc|prompt    default fc
#
# Every option has an environment default (BFCL_CATEGORIES, BFCL_LIMIT,
# BFCL_THREADS, BFCL_TEMPERATURE, BFCL_MAX_TOKENS, BFCL_REQUEST_TIMEOUT,
# BFCL_MODE) so a tier run can be tuned without editing eval-tier. EVAL_OUT
# overrides the results directory.
#
# See README.md here for what the categories are and why these.
set -uo pipefail

SUITE=bfcl
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=external/lib/remote.sh
source "$HERE/../lib/remote.sh"

usage() { sed -n '2,25p' "$0" | sed 's/^#\( \|$\)//'; exit 2; }
[[ $# -lt 2 ]] && usage

MODEL="$1"; URL="$(normalize_url "$2")"; shift 2
KEY_ENV=LLAMA_API_KEY
if [[ $# -gt 0 && "$1" != --* ]]; then KEY_ENV="$1"; shift; fi

# Single, multiple and parallel calls on synthetic and on user-contributed
# functions, abstaining when no function fits, and stateful multi-turn use.
CATEGORIES="${BFCL_CATEGORIES:-simple_python,multiple,parallel,parallel_multiple,irrelevance,live_simple,live_multiple,live_parallel,live_parallel_multiple,multi_turn_base}"
LIMIT="${BFCL_LIMIT:-30}"
THREADS="${BFCL_THREADS:-2}"
TEMPERATURE="${BFCL_TEMPERATURE:-}"
MAX_TOKENS="${BFCL_MAX_TOKENS:-8192}"
TIMEOUT="${BFCL_REQUEST_TIMEOUT:-1800}"
MODE="${BFCL_MODE:-fc}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --categories)  CATEGORIES="$2";  shift 2 ;;
    --limit)       LIMIT="$2";       shift 2 ;;
    --threads)     THREADS="$2";     shift 2 ;;
    --temperature) TEMPERATURE="$2"; shift 2 ;;
    --max-tokens)  MAX_TOKENS="$2";  shift 2 ;;
    --timeout)     TIMEOUT="$2";     shift 2 ;;
    --mode)        MODE="$2";        shift 2 ;;
    *) usage ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
SAFE_MODEL="${MODEL//\//_}"
OUT="${EVAL_OUT:-$REPO/external/results/$SAFE_MODEL/bfcl-$STAMP}"
RUN="$EVAL_ROOT/bfcl/runs/$SAFE_MODEL-$STAMP"

[[ "$LIMIT" =~ ^[0-9]+$ ]]  || die "--limit must be a whole number, 0 for every case"
[[ "$THREADS" =~ ^[1-9][0-9]*$ ]] || die "--threads must be a positive whole number"
[[ "$MAX_TOKENS" =~ ^[0-9]+$ ]]     || die "--max-tokens must be a whole number, 0 for no cap"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]]   || die "--timeout must be a positive whole number of seconds"
[[ -z "$TEMPERATURE" || "$TEMPERATURE" =~ ^[0-9]*\.?[0-9]+$ ]] || die "--temperature must be a number"
[[ "$MODE" == fc || "$MODE" == prompt ]] || die "--mode must be fc or prompt"
[[ "$LIMIT" == 0 ]] && LIMIT=""

KEY="$(key_from "$KEY_ENV" LLAMA_API_KEY)" || exit 1
remote_preflight bfcl

temperature_shown="${TEMPERATURE:-not sent, the endpoint samples as configured}"
max_tokens_shown="$MAX_TOKENS"; [[ "$MAX_TOKENS" == 0 ]] && max_tokens_shown="not sent"

mkdir -p "$OUT"
cat > "$OUT/run-config.txt" <<CONFIG
suite:         BFCL (bfcl-eval) through external/bfcl/launch.py, /v1/chat/completions
date:          $(date -Is)
wrapper:       $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown) $(git -C "$REPO" diff --quiet HEAD -- external 2>/dev/null || echo '(external/ modified)')
eval-server:   $EVAL_SERVER
model:         $MODEL
endpoint:      $URL
api-key:       from \$$KEY_ENV$([[ "$KEY" == none ]] && echo ' (unset: no authentication)')
mode:          $MODE
categories:    $CATEGORIES
limit:         ${LIMIT:-every case} per category
threads:       $THREADS
temperature:   $temperature_shown
max_tokens:    $max_tokens_shown
timeout:       ${TIMEOUT}s per request, no retries
CONFIG

remote_put "$RUN" "$HERE/launch.py" "$HERE/summarize.py" "$HERE/remote.sh" "$OUT/run-config.txt"

rc=0
remote_run_with_keys "$RUN" \
  "bash $(remote_quote "$RUN/remote.sh" "$RUN" "$MODEL" "$URL" "$CATEGORIES" "$LIMIT" "$THREADS" "$TEMPERATURE" "$MODE" "$MAX_TOKENS" "$TIMEOUT")" \
  "$KEY" || rc=$?

fetched=0
remote_fetch "$RUN" "$OUT" || fetched=$?
rm -rf "$OUT/.file_locks" "$OUT/launch.py" "$OUT/summarize.py" "$OUT/remote.sh" "$OUT/pid"
assert_no_key "$OUT" "$KEY"

summary() { python3 -c 'import json,sys; v = json.load(open(sys.argv[1]))[sys.argv[2]]; print("" if v is None else v)' "$OUT/summary.json" "$1" 2>/dev/null; }

if [[ $rc -eq 0 && $fetched -ne 0 ]]; then
  die "the run finished but its results could not be copied back — they are still at $EVAL_SERVER:$RUN"
fi
if [[ $rc -ne 0 ]]; then
  why="$(summary first_inference_error)"
  [[ -n "$why" ]] || why="$(last_log_line "$OUT/run.log")"
  die "the run failed on $EVAL_SERVER (exit $rc)${why:+: $why} — log in $OUT/run.log, run directory kept at $RUN"
fi

caveats=()
errors="$(summary inference_errors)"; truncated="$(summary truncated)"
[[ "${errors:-0}" == 0 ]] \
  || caveats+=("$errors of $(summary generated) cases are request failures that bfcl scored as wrong")
[[ "${truncated:-0}" == 0 ]] \
  || caveats+=("$truncated of $(summary generated) cases spent all $MAX_TOKENS tokens and were scored on a cut-off answer")
if [[ ${#caveats[@]} -gt 0 ]]; then
  ( IFS=';'; printf '%s\n' "${caveats[*]}" ) > "$OUT/CAVEAT"
fi

remote "rm -rf $(remote_quote "$RUN")"
printf '\nresults: %s\n' "$OUT"
