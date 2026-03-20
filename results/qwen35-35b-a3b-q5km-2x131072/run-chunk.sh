#!/usr/bin/env bash
# Usage: ./run-chunk.sh <chunk-file> <output-file>
# Sends a chunk of questions to the llama-server API and saves the response.
set -euo pipefail

CHUNK_FILE="$1"
OUTPUT_FILE="$2"
API_KEY="63a83819062c0946e9907b257b234be96cec03ea0fb388db716e95558ccf630d"
API_HOST="192.168.2.170"
API_PORT="8001"

PROMPT=$(cat "$CHUNK_FILE")

# Build JSON payload using jq to properly escape the prompt
PAYLOAD=$(jq -n \
  --arg content "$PROMPT" \
  '{
    "model": "qwen3.5-35b",
    "messages": [
      {"role": "system", "content": "You are a senior infrastructure and software engineer. Answer each question directly and thoroughly. Label each answer with its question ID (e.g., N1, L5, G3). Be concise but complete."},
      {"role": "user", "content": $content}
    ],
    "temperature": 0.1,
    "top_p": 0.95,
    "max_tokens": 24576
  }')

echo "Sending chunk to model..." >&2
START=$(date +%s)

# Use SSH tunnel to reach the API on localhost
RESPONSE=$(ssh ubuntu@${API_HOST} "curl -s http://127.0.0.1:${API_PORT}/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer ${API_KEY}' \
  -d '$(echo "$PAYLOAD" | sed "s/'/'\\\\''/g")'" 2>/dev/null)

END=$(date +%s)
ELAPSED=$((END - START))
echo "Chunk completed in ${ELAPSED}s" >&2

# Extract just the content from the response
echo "$RESPONSE" | jq -r '.choices[0].message.content // .content // "ERROR: No content in response"' > "$OUTPUT_FILE"

echo "Response saved to $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") lines)" >&2
