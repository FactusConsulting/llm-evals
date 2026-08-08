#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
K=$(cat /tmp/ai1-evalkey)
for i in 1 2 3 4 5; do
  echo "======= MXFP4 LOOP PASS ${i}/5 $(date +%H:%M:%S) ======="
  ./run-eval.sh --model-url http://192.168.2.170:8001 --model-name qwen3.6-35b-a3b-mxfp4 --api-key "$K" --verbose || echo "pass ${i} nonzero"
done
echo "MXFP4-LOOP-ALL-DONE"
