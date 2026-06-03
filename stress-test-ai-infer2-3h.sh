#!/usr/bin/env bash
# Continuous stress test for ai-infer2 — runs for at least 3 hours
# Loops 3-parallel-session eval rounds back-to-back until time limit hit.
set -euo pipefail

EVAL_DIR="/home/lars/source/llm-evals/results/qwen35-9b-vllm"
RUN_LOG="/home/lars/source/llm-evals/results/qwen35-9b-vllm/stress-3h-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_LOG"
MAIN_LOG="$RUN_LOG/main.log"

API_KEY="${API_KEY:?set the API_KEY environment variable}"
API_URL="http://192.168.2.171:8000"
DURATION_SECS=$((3 * 3600))   # 3 hours
START_TIME=$(date +%s)
DEADLINE=$((START_TIME + DURATION_SECS))

CHUNKS=(
  chunk1-networking-linux.txt
  chunk2-k8s-dev.txt
  chunk3-opentofu-ansible.txt
  chunk4-go-rust.txt
  chunk5-dotnet-python.txt
  chunk6-js-bash-powershell.txt
  chunk7-apparch-onprem.txt
  chunk8-cloud-ot.txt
  chunk9-scenarios.txt
)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$MAIN_LOG"; }

run_session() {
  local session=$1
  local round=$2
  local session_dir="$RUN_LOG/round${round}-session${session}"
  mkdir -p "$session_dir"
  local slog="$session_dir/session.log"
  log "round $round session $session: start"
  for chunk in "${CHUNKS[@]}"; do
    local out="$session_dir/${chunk%.txt}-response.txt"
    "$EVAL_DIR/run-chunk.sh" "$EVAL_DIR/chunks/$chunk" "$out" 2>>"$slog" || \
      echo "ERROR on $chunk" >> "$slog"
  done
  log "round $round session $session: done"
}

# GPU monitor — runs in background until script exits
gpu_monitor() {
  local glog="$RUN_LOG/gpu-monitor.log"
  while true; do
    STATUS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes ubuntu@192.168.2.171 \
      'nvidia-smi --query-gpu=index,utilization.gpu,temperature.gpu,power.draw,memory.used --format=csv,noheader,nounits 2>/dev/null' 2>/dev/null \
      || echo "SSH_FAILED")
    if echo "$STATUS" | grep -q "SSH_FAILED"; then
      echo "[$(date '+%H:%M:%S')] WARNING: GPU monitor SSH failed" | tee -a "$glog"
    else
      echo "[$(date '+%H:%M:%S')] $STATUS" | tee -a "$glog"
      # Alert if a GPU disappears (only 1 line instead of 2)
      GPU_COUNT=$(echo "$STATUS" | wc -l)
      if [[ $GPU_COUNT -lt 2 ]]; then
        echo "[$(date '+%H:%M:%S')] ALERT: Only $GPU_COUNT GPU(s) visible! Expected 2." | tee -a "$glog" "$MAIN_LOG"
      fi
    fi
    sleep 30
  done
}

log "=== 3-hour stress test start ==="
log "Deadline: $(date -d @$DEADLINE '+%H:%M:%S')"
log "Results: $RUN_LOG"

gpu_monitor &
MONITOR_PID=$!
trap "kill $MONITOR_PID 2>/dev/null; log '=== stress test aborted ==='" EXIT

ROUND=0
while [[ $(date +%s) -lt $DEADLINE ]]; do
  ROUND=$((ROUND + 1))
  ELAPSED=$(( $(date +%s) - START_TIME ))
  REMAINING=$(( DEADLINE - $(date +%s) ))
  log "=== Round $ROUND — elapsed ${elapsed_fmt:-${ELAPSED}s}, ${REMAINING}s remaining ==="

  # 3 parallel sessions
  run_session 1 $ROUND &
  P1=$!
  run_session 2 $ROUND &
  P2=$!
  run_session 3 $ROUND &
  P3=$!
  wait $P1 $P2 $P3

  log "=== Round $ROUND complete ==="

  # Check GPU health after each round
  GPU_STATUS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes ubuntu@192.168.2.171 \
    'nvidia-smi --query-gpu=index,utilization.gpu,temperature.gpu,power.draw --format=csv,noheader' 2>/dev/null \
    || echo "UNREACHABLE")
  log "GPU post-round: $GPU_STATUS"

  # Check vLLM still up
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
    -H "Authorization: Bearer $API_KEY" "$API_URL/v1/models" 2>/dev/null || echo "000")
  if [[ "$HTTP" != "200" ]]; then
    log "WARNING: vLLM returned HTTP $HTTP after round $ROUND"
  fi
done

kill $MONITOR_PID 2>/dev/null || true
trap - EXIT

log "=== 3-hour stress test COMPLETE after $ROUND rounds ==="
log "Final GPU state:"
ssh -o ConnectTimeout=10 -o BatchMode=yes ubuntu@192.168.2.171 \
  'nvidia-smi --query-gpu=index,utilization.gpu,temperature.gpu,power.draw,memory.used --format=csv,noheader' 2>/dev/null \
  | tee -a "$MAIN_LOG"
