#!/usr/bin/env bash
# Run all 5 runs × 9 chunks for Q5_K_L 524k turbo4. Skips chunks that already
# completed successfully (have a non-empty file without ERROR markers).
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

NUM_RUNS=${NUM_RUNS:-5}
echo "=== Q5_K_L 524k turbo4: $NUM_RUNS runs × ${#CHUNKS[@]} chunks ==="
for run in $(seq 1 "$NUM_RUNS"); do
  RUN_DIR="run${run}"
  mkdir -p "$RUN_DIR"
  echo ""
  echo "--- run $run/$NUM_RUNS ---"
  for i in "${!CHUNKS[@]}"; do
    n=$((i + 1))
    chunk="${CHUNKS[$i]}"
    output="$RUN_DIR/chunk${n}-response.txt"
    if [[ -f "$output" && -s "$output" ]] && ! grep -q "ERROR" "$output"; then
      echo "  chunk $n: cached, skipping"
      continue
    fi
    echo "  chunk $n: $chunk → $output"
    ./run-chunk.sh "chunks/$chunk" "$output" 2>&1 | tail -3
  done
done
echo ""
echo "=== done at $(date -Is) ==="
