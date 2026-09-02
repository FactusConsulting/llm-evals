#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "=== Q6_K ai-infer1 Python+Scenarios eval, 5 runs ==="
for run in 1 2 3 4 5; do
  RUN_DIR="run${run}"
  mkdir -p "$RUN_DIR"
  echo ""
  echo "--- run $run/5 ---"
  for chunk in chunk5-dotnet-python.txt chunk9-scenarios.txt; do
    name=$(basename $chunk .txt | grep -oP 'chunk\d+')
    output="$RUN_DIR/${name}-response.txt"
    if [[ -f "$output" && -s "$output" ]] && ! grep -q "ERROR" "$output"; then
      echo "  $name: cached, skipping"
      continue
    fi
    echo "  $name: $chunk → $output"
    ./run-chunk.sh "chunks/$chunk" "$output" 2>&1 | tail -3
  done
done
echo ""
echo "=== done at $(date -Is) ==="
