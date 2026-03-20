#!/usr/bin/env bash
# Run benchmarks 3-5 sequentially, with 2 chunks in parallel per batch
set -euo pipefail
cd /home/lars/source/llm-evals/results/qwen35-35b-a3b-q5km-2x131072

for RUN in 3 4 5; do
  echo "=== Starting Run $RUN ==="
  mkdir -p "run${RUN}"
  START=$(date +%s)

  # Batch 1: chunks 1+2
  bash send-chunk.sh chunks/chunk1-networking-linux.txt "run${RUN}/chunk1-response.txt" &
  P1=$!
  bash send-chunk.sh chunks/chunk2-k8s-dev.txt "run${RUN}/chunk2-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 2: chunks 3+4
  bash send-chunk.sh chunks/chunk3-opentofu-ansible.txt "run${RUN}/chunk3-response.txt" &
  P1=$!
  bash send-chunk.sh chunks/chunk4-go-rust.txt "run${RUN}/chunk4-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 3: chunks 5+6
  bash send-chunk.sh chunks/chunk5-dotnet-python.txt "run${RUN}/chunk5-response.txt" &
  P1=$!
  bash send-chunk.sh chunks/chunk6-js-bash-powershell.txt "run${RUN}/chunk6-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 4: chunks 7+8
  bash send-chunk.sh chunks/chunk7-apparch-onprem.txt "run${RUN}/chunk7-response.txt" &
  P1=$!
  bash send-chunk.sh chunks/chunk8-cloud-ot.txt "run${RUN}/chunk8-response.txt" &
  P2=$!
  wait $P1 $P2

  # Batch 5: chunk 9 (scenarios - single)
  bash send-chunk.sh chunks/chunk9-scenarios.txt "run${RUN}/chunk9-response.txt"

  END=$(date +%s)
  echo "=== Run $RUN completed in $((END - START))s ==="
done

echo "All runs complete!"
