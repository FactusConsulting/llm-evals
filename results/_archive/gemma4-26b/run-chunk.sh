#!/usr/bin/env bash
set -euo pipefail
CHUNK_FILE="$1"
OUTPUT_FILE="$2"
API_KEY="${API_KEY:?set the API_KEY environment variable}"
API_URL="https://ai2.lwa.dk/v1/chat/completions"

PROMPT=$(cat "$CHUNK_FILE")
PAYLOAD=$(jq -n \
  --arg content "$PROMPT" \
  '{
    "model": "gemma4-26b",
    "messages": [
      {"role": "system", "content": "You are a senior infrastructure and software engineer. Answer each question directly and thoroughly. Label each answer with its question ID (e.g., N1, L5, G3). Be concise but complete."},
      {"role": "user", "content": $content}
    ],
    "temperature": 0.1,
    "top_p": 0.95,
    "max_tokens": 24576
  }')

echo "Sending chunk to gemma4-26b..." >&2
START=$(date +%s)
RESPONSE=$(curl -s --max-time 1800 "$API_URL" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $API_KEY" \
  -d "$PAYLOAD" 2>/dev/null)
END=$(date +%s)
echo "Chunk completed in $((END - START))s" >&2

if echo "$RESPONSE" | jq -e '.choices[0].message.content' > /dev/null 2>&1; then
  echo "$RESPONSE" | jq -r '.choices[0].message.content' > "$OUTPUT_FILE"
  echo "Saved to $OUTPUT_FILE" >&2
else
  echo "ERROR: Unexpected response: $(echo "$RESPONSE" | head -c 500)" | tee "$OUTPUT_FILE" >&2
  exit 1
fi
