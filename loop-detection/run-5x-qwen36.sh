#!/usr/bin/env bash
# Loop-detection eval x5 against qwen3.6-35b-a3b (ai-infer2:8001, MTP).
set -uo pipefail
cd "$(dirname "$0")"
K=$(cat /tmp/qwen36-evalkey)
for i in 1 2 3 4 5; do
  echo "================ LOOP-DETECTION PASS ${i}/5 $(date +%H:%M:%S) ================"
  ./run-eval.sh \
    --model-url http://192.168.2.171:8001 \
    --model-name qwen3.6-35b-a3b \
    --api-key "$K" \
    --verbose || echo "LOOP pass ${i} returned nonzero"
done
echo "LOOP-ALL-DONE"
