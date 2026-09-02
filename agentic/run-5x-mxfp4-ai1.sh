#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
K=$(cat /tmp/ai1-evalkey)
for i in 1 2 3 4 5; do
  echo "======= MXFP4 AGENTIC PASS ${i}/5 $(date +%H:%M:%S) ======="
  python3 -u harness.py --model-url http://192.168.2.170:8001 --model-name qwen3.6-35b-a3b-mxfp4 --api-key "$K" --exec-host ubuntu@192.168.2.175 --all --verbose 2>&1 | grep -E "TOTAL:|Tasks:" || echo "pass ${i} nonzero"
done
echo "MXFP4-AGENTIC-ALL-DONE"
