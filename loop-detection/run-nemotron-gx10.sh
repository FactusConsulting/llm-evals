#!/usr/bin/env bash
# Loop-detection eval x3 against qwen3.6-35b-a3b BF16 on GX10 (:8080, no-auth).
set -uo pipefail
cd "$(dirname "$0")"
for i in 1 2; do
  echo "================ LOOP-DETECTION PASS ${i}/2 $(date +%H:%M:%S) ================"
  ./run-eval.sh \
    --model-url http://192.168.2.173:8080 \
    --model-name nemotron-3-super-120b \
    --api-key dummy \
    --verbose || echo "LOOP pass ${i} returned nonzero"
done
echo "LOOP-ALL-DONE"
