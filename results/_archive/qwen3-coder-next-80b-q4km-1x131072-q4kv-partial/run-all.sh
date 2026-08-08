#!/usr/bin/env bash
# Benchmark: Qwen3-Coder-Next 80B dense, Q4_K_M, partial GPU offload (ngl 28)
# Hardware: 2x RTX 5060 Ti 16GB + 48GB RAM, llama.cpp b8373 + CUDA 13.0
# 1 slot only — no parallel chunks
set -euo pipefail
BASEDIR="$(cd "$(dirname "$0")" && pwd)"
CHUNKS_DIR="/home/lars/source/llm-evals/results/qwen35-35b-a3b-q5km-2x131072/chunks"
SEND_SCRIPT="/home/lars/source/llm-evals/results/qwen35-35b-a3b-q5km-2x131072/send-chunk.sh"
cd "$BASEDIR"
for RUN in 1 2 3; do
  echo "=== Starting Run $RUN ==="
  mkdir -p "run${RUN}"
  START=$(date +%s)
  for CHUNK in 1 2 3 4 5 6 7 8 9; do
    CNAME=$(ls "$CHUNKS_DIR"/chunk${CHUNK}-*.txt)
    bash "$SEND_SCRIPT" "$CNAME" "run${RUN}/chunk${CHUNK}-response.txt"
  done
  END=$(date +%s)
  echo "=== Run $RUN completed in $((END - START))s ==="
done
echo "All runs complete!"
