#!/usr/bin/env bash
# Run 5 benchmark runs with q4_0 KV cache, 2 chunks in parallel per batch
set -euo pipefail

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
CHUNKS_DIR="/home/lars/source/llm-evals/results/qwen35-35b-a3b-q5km-2x131072/chunks"
SEND_SCRIPT="/home/lars/source/llm-evals/results/qwen35-35b-a3b-q5km-2x131072/send-chunk.sh"

cd "$BASEDIR"

for RUN in 1 2 3 4 5; do
  echo "=== Starting Run $RUN ==="
  mkdir -p "run${RUN}"
  START=$(date +%s)

  # Batch 1: chunks 1+2
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk1-networking-linux.txt" "run${RUN}/chunk1-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk2-k8s-dev.txt" "run${RUN}/chunk2-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 2: chunks 3+4
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk3-opentofu-ansible.txt" "run${RUN}/chunk3-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk4-go-rust.txt" "run${RUN}/chunk4-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 3: chunks 5+6
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk5-dotnet-python.txt" "run${RUN}/chunk5-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk6-js-bash-powershell.txt" "run${RUN}/chunk6-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 4: chunks 7+8
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk7-apparch-onprem.txt" "run${RUN}/chunk7-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk8-cloud-ot.txt" "run${RUN}/chunk8-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 5: chunk 9 (scenarios - single)
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk9-scenarios.txt" "run${RUN}/chunk9-response.txt"

  END=$(date +%s)
  echo "=== Run $RUN completed in $((END - START))s ==="
done

echo "All 5 runs complete!"
