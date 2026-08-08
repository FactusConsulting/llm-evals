#!/usr/bin/env bash
# Head-to-head: same 30-task agentic suite x5 against the LIVE Gemma 26B on ai-infer1.
# Commands execute on the eval-server (192.168.2.175).
set -uo pipefail
cd "$(dirname "$0")"
K=$(cat /tmp/ai1-evalkey)
for i in 1 2 3 4 5; do
  echo "================ AGENTIC(gemma26b) PASS ${i}/5 $(date +%H:%M:%S) ================"
  python3 -u harness.py \
    --model-url http://192.168.2.170:8001 \
    --model-name gemma4-26b \
    --api-key "$K" \
    --exec-host ubuntu@192.168.2.175 \
    --all --verbose 2>&1 | grep -E "TOTAL:|Tasks:|\[PASS\]|\[FAIL\]|\[PARTIAL\]|^  AG|Results saved" || echo "pass ${i} returned nonzero"
done
echo "GEMMA26B-AGENTIC-ALL-DONE"
