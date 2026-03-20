#!/usr/bin/env bash
# Usage: ./send-chunk.sh <chunk-file> <output-file>
# Sends a chunk of questions to the llama-server API via SSH tunnel and saves the response.
set -euo pipefail

CHUNK_FILE="$1"
OUTPUT_FILE="$2"
API_KEY="63a83819062c0946e9907b257b234be96cec03ea0fb388db716e95558ccf630d"
API_URL="http://localhost:18001/v1/chat/completions"

PROMPT=$(cat "$CHUNK_FILE")

TMPJSON=$(mktemp /tmp/chunk-payload.XXXXXX.json)
trap "rm -f $TMPJSON" EXIT

jq -n \
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
  }' > "$TMPJSON"

echo "Sending chunk $(basename "$CHUNK_FILE") to model..." >&2
START=$(date +%s)

RESPONSE=$(curl -s --max-time 600 "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d @"$TMPJSON")

END=$(date +%s)
ELAPSED=$((END - START))
echo "Chunk completed in ${ELAPSED}s" >&2

echo "$RESPONSE" | jq -r '.choices[0].message.content // "ERROR: No content"' > "$OUTPUT_FILE"
echo "Saved to $OUTPUT_FILE ($(wc -c < "$OUTPUT_FILE") bytes)" >&2
