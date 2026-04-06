#!/usr/bin/env bash
# Stress test ai-infer2: all 9 eval chunks × 3 parallel sessions
# Designed to saturate both GPUs and verify stability under sustained load.
set -euo pipefail

EVAL_DIR="/home/lars/source/llm-evals/results/qwen35-9b-vllm"
LOG_DIR="/home/lars/source/llm-evals/results/qwen35-9b-vllm/stress-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_DIR"

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

run_session() {
  local session=$1
  local session_dir="$LOG_DIR/session${session}"
  mkdir -p "$session_dir"
  local log="$session_dir/session.log"

  echo "[session $session] starting at $(date)" | tee -a "$log"

  for chunk in "${CHUNKS[@]}"; do
    local chunk_base="${chunk%.txt}"
    local output="$session_dir/${chunk_base}-response.txt"
    echo "[session $session] sending $chunk..." | tee -a "$log"
    "$EVAL_DIR/run-chunk.sh" "$EVAL_DIR/chunks/$chunk" "$output" 2>>"$log"
    echo "[session $session] done: $chunk" | tee -a "$log"
  done

  echo "[session $session] ALL CHUNKS DONE at $(date)" | tee -a "$log"
}

echo "Starting 3 parallel sessions — $(date)"
echo "Results: $LOG_DIR"
echo ""

# Launch all 3 sessions in parallel
run_session 1 &
PID1=$!
run_session 2 &
PID2=$!
run_session 3 &
PID3=$!

# Monitor GPU every 30s while running
(
  while kill -0 $PID1 2>/dev/null || kill -0 $PID2 2>/dev/null || kill -0 $PID3 2>/dev/null; do
    STATUS=$(ssh -o ConnectTimeout=5 ubuntu@192.168.2.171 \
      'nvidia-smi --query-gpu=index,utilization.gpu,temperature.gpu,power.draw,memory.used --format=csv,noheader,nounits 2>/dev/null' 2>/dev/null || echo "ssh failed")
    echo "[$(date +%H:%M:%S)] GPU: $STATUS" | tee -a "$LOG_DIR/gpu-monitor.log"
    sleep 30
  done
) &
MONITOR_PID=$!

wait $PID1 && echo "Session 1 OK" || echo "Session 1 FAILED"
wait $PID2 && echo "Session 2 OK" || echo "Session 2 FAILED"
wait $PID3 && echo "Session 3 OK" || echo "Session 3 FAILED"

kill $MONITOR_PID 2>/dev/null || true

echo ""
echo "=== Stress test complete: $(date) ==="
echo "Results in: $LOG_DIR"
echo ""
echo "=== Final GPU state ==="
ssh ubuntu@192.168.2.171 \
  'nvidia-smi --query-gpu=index,utilization.gpu,temperature.gpu,power.draw,memory.used --format=csv,noheader 2>/dev/null' 2>/dev/null || true
