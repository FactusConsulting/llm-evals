#!/usr/bin/env bash
# Runs ON the eval server, inside the run directory run.sh created there. The
# API key is the first line of stdin and exists only in this process's
# environment.
set -euo pipefail

IFS= read -r OPENAI_API_KEY
export OPENAI_API_KEY

RUN="$1"
echo $$ > "$RUN/pid"
export BFCL_MODEL="$2" OPENAI_BASE_URL="$3" BFCL_CATEGORIES="$4" BFCL_LIMIT="$5"
THREADS="$6"
export BFCL_TEMPERATURE="$7" BFCL_MODE="$8" BFCL_MAX_TOKENS="$9" BFCL_REQUEST_TIMEOUT="${10}"
export BFCL_PROJECT_ROOT="$RUN"

PY="${EVAL_ROOT:-/opt/evals}/bfcl/.venv/bin/python"

generate=(generate --model "$BFCL_MODEL" --test-category "$BFCL_CATEGORIES"
          --num-threads "$THREADS")
# bfcl always hands its handler a temperature; launch.py drops it from the
# request unless BFCL_TEMPERATURE is set.
[[ -n "$BFCL_TEMPERATURE" ]] && generate+=(--temperature "$BFCL_TEMPERATURE")
evaluate=(evaluate --model "$BFCL_MODEL" --test-category "$BFCL_CATEGORIES")
if [[ -n "$BFCL_LIMIT" ]]; then
  generate+=(--run-ids)
  evaluate+=(--partial-eval)
fi

cd "$RUN"
{
  printf 'bfcl-eval:     %s\n' "$("$PY" -c 'from importlib.metadata import version; print(version("bfcl-eval"))')"
  printf 'python:        %s\n' "$("$PY" -V 2>&1)"
  printf 'generate:      launch.py %s\n' "${generate[*]@Q}"
  printf 'evaluate:      launch.py %s\n' "${evaluate[*]@Q}"
} >> run-config.txt

"$PY" launch.py "${generate[@]}" 2>&1 | tee -a run.log
"$PY" launch.py "${evaluate[@]}" 2>&1 | tee -a run.log
"$PY" summarize.py "$RUN" "$BFCL_MAX_TOKENS" 2>&1 | tee -a run.log
