#!/usr/bin/env bash
# Benchmark: Qwen3.5-35B-A3B Q5_K_M, 2x262144 per slot (524288 total), q4_0 KV cache
# Hardware: 2x RTX 5060 Ti 16GB, 24GB RAM (no balloon), llama.cpp b8373 + CUDA 13.0
set -euo pipefail
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
CHUNKS_DIR="/home/lars/source/llm-evals/results/qwen35-35b-a3b-q5km-2x131072/chunks"
SEND_SCRIPT="/home/lars/source/llm-evals/results/qwen35-35b-a3b-q5km-2x131072/send-chunk.sh"
cd "$BASEDIR"
for RUN in 1 2 3 4 5; do
  echo "=== Starting Run $RUN ==="
  mkdir -p "run${RUN}"
  START=$(date +%s)
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk1-networking-linux.txt" "run${RUN}/chunk1-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk2-k8s-dev.txt" "run${RUN}/chunk2-response.txt" &
  P2=$!
  wait $P1 $P2
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk3-opentofu-ansible.txt" "run${RUN}/chunk3-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk4-go-rust.txt" "run${RUN}/chunk4-response.txt" &
  P2=$!
  wait $P1 $P2
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk5-dotnet-python.txt" "run${RUN}/chunk5-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk6-js-bash-powershell.txt" "run${RUN}/chunk6-response.txt" &
  P2=$!
  wait $P1 $P2
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk7-apparch-onprem.txt" "run${RUN}/chunk7-response.txt" &
  P1=$!
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk8-cloud-ot.txt" "run${RUN}/chunk8-response.txt" &
  P2=$!
  wait $P1 $P2
  bash "$SEND_SCRIPT" "$CHUNKS_DIR/chunk9-scenarios.txt" "run${RUN}/chunk9-response.txt"
  END=$(date +%s)
  echo "=== Run $RUN completed in $((END - START))s ==="
done
echo "All 5 runs complete!"
