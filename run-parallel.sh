#!/usr/bin/env bash
# Run all 5 evaluation runs for both models IN PARALLEL (different hosts)
# Usage: ./run-parallel.sh
# Logs: results/qwen35-27b-opus-distilled-q4km/run.log
#        results/qwen35-9b-q8_0/run.log
set -euo pipefail
cd "$(dirname "$0")"

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

run_model() {
  local model_dir="$1"
  local model_name="$2"
  local log="${model_dir}/run.log"

  echo "[$(date '+%H:%M:%S')] Starting evals for: $model_name" | tee "$log"

  for run in 1 2 3 4 5; do
    local run_dir="${model_dir}/run${run}"
    mkdir -p "$run_dir"
    echo "[$(date '+%H:%M:%S')] Run ${run}/5 for ${model_name}" | tee -a "$log"

    for ((i=0; i<${#CHUNKS[@]}; i++)); do
      local chunk="${CHUNKS[$i]}"
      local chunk_num=$((i + 1))
      local output="${run_dir}/chunk${chunk_num}-response.txt"

      if [[ -f "$output" && -s "$output" ]] && ! grep -q "ERROR" "$output"; then
        echo "  Chunk ${chunk_num} already done, skipping" | tee -a "$log"
        continue
      fi

      echo "[$(date '+%H:%M:%S')]   Chunk ${chunk_num}/${#CHUNKS[@]}: ${chunk}" | tee -a "$log"
      if "${model_dir}/run-chunk.sh" "${model_dir}/chunks/${chunk}" "$output" 2>>"$log"; then
        echo "[$(date '+%H:%M:%S')]   Chunk ${chunk_num} OK ($(wc -l < "$output") lines)" | tee -a "$log"
      else
        echo "[$(date '+%H:%M:%S')]   Chunk ${chunk_num} FAILED" | tee -a "$log"
      fi
    done

    echo "[$(date '+%H:%M:%S')] Run ${run} complete for ${model_name}" | tee -a "$log"
  done

  echo "[$(date '+%H:%M:%S')] All 5 runs complete for ${model_name}" | tee -a "$log"
}

echo "Starting parallel eval runs at $(date)"
echo "27B log: results/qwen35-27b-opus-distilled-q4km/run.log"
echo "9B log:  results/qwen35-9b-q8_0/run.log"

# Run both in parallel — they're on different hosts
run_model "results/qwen35-27b-opus-distilled-q4km" "27B-Opus-Distilled" &
PID_27B=$!

run_model "results/qwen35-9b-q8_0" "9B-Q8_0" &
PID_9B=$!

echo "27B PID: $PID_27B, 9B PID: $PID_9B"
echo "Waiting for both to complete..."

wait $PID_27B
echo "27B complete (exit $?)"
wait $PID_9B
echo "9B complete (exit $?)"

echo "All evaluations finished at $(date)"
