#!/usr/bin/env bash
# Runs ON the eval server, inside the run directory run.sh created there. Stdin
# carries two lines: the agent endpoint's key, then the user simulator's. They
# exist only in this process's environment; the tau2 command line and
# results.json name the variables (LiteLLM resolves "os.environ/<NAME>" when it
# makes the request), never the values.
set -euo pipefail

IFS= read -r TAU2_AGENT_API_KEY
IFS= read -r TAU2_USER_API_KEY
export TAU2_AGENT_API_KEY TAU2_USER_API_KEY

RUN="$1"; DOMAIN="$2"
echo $$ > "$RUN/pid"
AGENT_LLM="$3"; AGENT_ARGS="$4"
USER_LLM="$5";  USER_ARGS="$6"
NUM_TASKS="$7"; NUM_TRIALS="$8"; CONCURRENCY="$9"; SEED="${10}"; MAX_TOKENS="${11}"

ROOT="${EVAL_ROOT:-/opt/evals}/tau2"
BIN="$ROOT/.venv/bin"

# tau2 writes simulations into its data directory. The run gets its own, with
# the pinned task data linked in, so the checkout stays clean and two runs
# cannot collide.
export TAU2_DATA_DIR="$RUN/data"
mkdir -p "$TAU2_DATA_DIR"
[[ -d "$ROOT/src/data/tau2/domains/$DOMAIN" ]] \
  || { echo "no task data for domain '$DOMAIN' under $ROOT/src — run setup-eval-server.sh" >&2; exit 4; }
ln -sfn "$ROOT/src/data/tau2" "$TAU2_DATA_DIR/tau2"

run=(run --domain "$DOMAIN"
     --agent-llm "$AGENT_LLM" --agent-llm-args "$AGENT_ARGS"
     --user-llm "$USER_LLM" --user-llm-args "$USER_ARGS"
     --num-trials "$NUM_TRIALS" --max-concurrency "$CONCURRENCY" --seed "$SEED"
     --save-to results --auto-resume)
[[ -n "$NUM_TASKS" ]] && run+=(--num-tasks "$NUM_TASKS")

{
  printf 'tau2:          %s\n' "$("$BIN/python" -c 'from importlib.metadata import version; print(version("tau2"))')"
  printf 'tau2 commit:   %s\n' "$(git -C "$ROOT/src" rev-parse HEAD)"
  printf 'python:        %s\n' "$("$BIN/python" -V 2>&1)"
  printf 'command:       tau2 %s\n' "${run[*]@Q}"
} >> "$RUN/run-config.txt"

# tau2 stamps results.json with `git rev-parse HEAD` of its working directory;
# from the pinned checkout that is the commit the tasks came from.
cd "$ROOT/src"
"$BIN/tau2" "${run[@]}" 2>&1 | tee -a "$RUN/run.log"
"$BIN/python" "$RUN/summarize.py" "$TAU2_DATA_DIR/simulations/results" "$RUN" "$MAX_TOKENS" 2>&1 | tee -a "$RUN/run.log"
