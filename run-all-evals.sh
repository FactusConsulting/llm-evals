#!/usr/bin/env bash
# Run all 5 evaluation runs for both models
# Usage: ./run-all-evals.sh
set -euo pipefail

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
  local parallel="$3"  # max parallel chunks

  echo "============================================="
  echo "  Running evals for: $model_name"
  echo "============================================="

  for run in 1 2 3 4 5; do
    local run_dir="${model_dir}/run${run}"
    mkdir -p "$run_dir"
    echo ""
    echo "--- Run ${run}/5 for ${model_name} ---"

    for ((i=0; i<${#CHUNKS[@]}; i++)); do
      local chunk="${CHUNKS[$i]}"
      local chunk_num=$((i + 1))
      local output="${run_dir}/chunk${chunk_num}-response.txt"

      if [[ -f "$output" && -s "$output" ]] && ! grep -q "ERROR" "$output"; then
        echo "  Chunk ${chunk_num} already done, skipping"
        continue
      fi

      echo "  Sending chunk ${chunk_num}/${#CHUNKS[@]}: ${chunk}"
      "${model_dir}/run-chunk.sh" "${model_dir}/chunks/${chunk}" "$output"
    done

    echo "--- Run ${run} complete ---"
  done
}

cd "$(dirname "$0")"

# Run 27B (1 slot, sequential)
run_model "results/qwen35-27b-opus-distilled-q4km" "Qwen3.5-27B-Opus-Distilled Q4_K_M" 1

# Run 9B (2 slots, but run sequentially to keep it simple)
run_model "results/qwen35-9b-q8_0" "Qwen3.5-9B Q8_0" 1

echo ""
echo "============================================="
echo "  All eval runs complete!"
echo "============================================="
