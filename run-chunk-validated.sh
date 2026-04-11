#!/usr/bin/env bash
# Validated run-chunk with anti-cache measures.
# Each request gets a unique system prompt to prevent llama-server prefix caching.
set -euo pipefail

CHUNK_FILE="$1"
OUTPUT_FILE="$2"
API_URL="$3"
API_KEY="$4"
MODEL_NAME="$5"
MAX_RETRIES=2

# Extract expected question ID prefixes from the chunk file (match anywhere, not just line start)
EXPECTED_IDS=$(grep -oP '[A-Z]{1,2}[0-9]+' "$CHUNK_FILE" | head -5 | sed 's/[0-9]*//' | sort -u | tr '\n' '|' | sed 's/|$//')
FIRST_ID=$(grep -oP '[A-Z]{1,2}[0-9]+' "$CHUNK_FILE" | head -1)
CHUNK_TOPIC=$(head -5 "$CHUNK_FILE" | grep -oP '## .+' | head -1 | sed 's/## //')
: "${EXPECTED_IDS:=SC}" "${FIRST_ID:=SC1}" "${CHUNK_TOPIC:=General}"

echo "Topic: $CHUNK_TOPIC | Expected: $EXPECTED_IDS (first: $FIRST_ID)" >&2

PROMPT=$(cat "$CHUNK_FILE")

for attempt in $(seq 0 "$MAX_RETRIES"); do
  if [[ $attempt -gt 0 ]]; then
    echo "RETRY $attempt/$MAX_RETRIES" >&2
    sleep 3
  fi

  # Unique nonce per attempt prevents llama-server from reusing cached KV state
  NONCE="eval-$(date +%s%N)-$$-${RANDOM}"

  # Build payload with unique system prompt — the nonce at the start ensures
  # no two requests share a prompt prefix, defeating slot KV cache reuse.
  PAYLOAD=$(jq -n \
    --arg content "$PROMPT" \
    --arg model "$MODEL_NAME" \
    --arg nonce "$NONCE" \
    --arg topic "$CHUNK_TOPIC" \
    --arg first_id "$FIRST_ID" \
    '{
      "model": $model,
      "messages": [
        {"role": "system", "content": ("SESSION=" + $nonce + "\nYou are a senior infrastructure and software engineer.\nTOPIC: " + $topic + "\nAnswer each question with its ID (starting from " + $first_id + "). Answer ONLY the questions in this message.")},
        {"role": "user", "content": $content}
      ],
      "temperature": 0.1,
      "top_p": 0.95,
      "max_tokens": 24576
    }')

  echo "Sending to $MODEL_NAME [nonce=$NONCE] (attempt $((attempt+1)))..." >&2
  START=$(date +%s)
  RESPONSE=$(curl -s --max-time 1800 "$API_URL" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $API_KEY" \
    -d "$PAYLOAD" 2>/dev/null)
  END=$(date +%s)
  echo "Completed in $((END - START))s" >&2

  CONTENT=$(echo "$RESPONSE" | python3 -c "
import json, sys, re
raw = sys.stdin.read()
cleaned = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', raw)
try:
    d = json.loads(cleaned)
    msg = d['choices'][0]['message']
    content = msg.get('content', '') or ''
    if len(content) < 100:
        print('ERROR: Content too short (' + str(len(content)) + ' chars)', file=sys.stderr)
        sys.exit(1)
    print(content)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || { echo "ERROR: Parse failed or content too short" >&2; continue; }

  # Validate: question IDs in response should match expected
  MATCH_COUNT=$(echo "$CONTENT" | grep -coP "($EXPECTED_IDS)[0-9]" || true)

  if [[ $MATCH_COUNT -lt 3 ]]; then
    echo "VALIDATION FAILED: $MATCH_COUNT matches for [$EXPECTED_IDS]. First 5 ID prefixes in response: [$FIRST_5]" >&2
    if [[ $attempt -eq $MAX_RETRIES ]]; then
      echo "GIVING UP" >&2
      exit 1
    fi
    continue
  fi

  echo "VALIDATED: $MATCH_COUNT IDs match [$EXPECTED_IDS]" >&2
  echo "$CONTENT" > "$OUTPUT_FILE"
  echo "Saved to $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") lines)" >&2
  exit 0
done
