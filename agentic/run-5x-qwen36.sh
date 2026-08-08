#!/usr/bin/env bash
# Agentic eval: all tasks (all tiers) x5 against qwen3.6-35b-a3b (ai-infer2:8001).
# Commands execute on the eval-server (192.168.2.175). Each pass writes a timestamped result file.
set -uo pipefail
cd "$(dirname "$0")"
K=$(cat /tmp/qwen36-evalkey)
for i in 1 2 3 4 5; do
  echo "================ AGENTIC PASS ${i}/5 $(date +%H:%M:%S) ================"
  python3 -u harness.py \
    --model-url http://192.168.2.171:8001 \
    --model-name qwen3.6-35b-a3b \
    --api-key "$K" \
    --exec-host ubuntu@192.168.2.175 \
    --all --verbose 2>&1 | grep -E "TOTAL:|Tasks:|\[PASS\]|\[FAIL\]|\[PARTIAL\]|^  AG|Results saved" || echo "AGENTIC pass ${i} returned nonzero"
done
echo "AGENTIC-ALL-DONE"
