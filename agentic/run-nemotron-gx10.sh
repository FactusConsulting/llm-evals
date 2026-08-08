#!/usr/bin/env bash
# Agentic eval: all tasks x1 against qwen3.6-35b-a3b BF16 on GX10 (:8080, no-auth).
set -uo pipefail
cd "$(dirname "$0")"
echo "================ AGENTIC PASS 1/1 $(date +%H:%M:%S) ================"
python3 -u harness.py \
  --model-url http://192.168.2.173:8080 \
  --model-name nemotron-3-super-120b \
  --api-key dummy \
  --exec-host ubuntu@192.168.2.175 \
  --all --verbose 2>&1 | grep -E "TOTAL:|Tasks:|\[PASS\]|\[FAIL\]|\[PARTIAL\]|^  AG|Results saved" || echo "AGENTIC returned nonzero"
echo "AGENTIC-ALL-DONE"
