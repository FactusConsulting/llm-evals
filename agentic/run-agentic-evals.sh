#!/usr/bin/env bash
# Run agentic evals against both local models
set -euo pipefail
cd "$(dirname "$0")"

# API keys
KEY_27B=$(ssh -o StrictHostKeyChecking=no ubuntu@192.168.2.170 "sudo cat /etc/llama-api-key" 2>/dev/null)
KEY_9B=$(ssh -o StrictHostKeyChecking=no ubuntu@192.168.2.171 "sudo cat /etc/llama-api-key" 2>/dev/null)

TIER="${1:-1}"

echo "Running Tier $TIER agentic evals"
echo ""

echo "=== Qwen3.5-9B (ai-infer2) ==="
python3 harness.py \
    --model-url http://192.168.2.171:8001 \
    --model-name qwen3.5-9b \
    --api-key "$KEY_9B" \
    --tier "$TIER" \
    --verbose

echo ""
echo "=== Qwen3.5-27B Opus Distilled (ai-infer1) ==="
python3 harness.py \
    --model-url http://192.168.2.170:8001 \
    --model-name qwen3.5-27b-opus \
    --api-key "$KEY_27B" \
    --tier "$TIER" \
    --verbose

echo ""
echo "Done! Results in results/"
