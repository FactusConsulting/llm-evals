#!/usr/bin/env bash
set -euo pipefail
CHUNK_FILE="$1"
OUTPUT_FILE="$2"
API_KEY="${API_KEY:?set the API_KEY environment variable}"
API_URL="http://192.168.2.173:8080/v1/chat/completions"

PROMPT=$(cat "$CHUNK_FILE")
PAYLOAD=$(jq -n \
  --arg content "$PROMPT" \
  '{
    "model": "qwen3.6-27b",
    "messages": [
      {"role": "system", "content": "You are a senior infrastructure and software engineer. Answer each question directly and thoroughly. Label each answer with its question ID (e.g., N1, L5, G3). Be concise but complete."},
      {"role": "user", "content": $content}
    ],
    "temperature": 0.1,
    "top_p": 0.95,
    "max_tokens": 24576
  }')

echo "Sending chunk to qwen3.6-27b..." >&2
START=$(date +%s)
RESPONSE=$(curl -s --max-time 9000 "$API_URL" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $API_KEY" \
  -d "$PAYLOAD" 2>/dev/null)
END=$(date +%s)
echo "Chunk completed in $((END - START))s" >&2

echo "$RESPONSE" | python3 -c "
import json, sys, re
raw = sys.stdin.read()
cleaned = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', raw)
try:
    d = json.loads(cleaned)
    msg = d['choices'][0]['message']
    content = msg.get('content', '') or ''
    reasoning = msg.get('reasoning_content', '') or ''
    best = content if len(content) > 200 else reasoning
    if len(best) < 100:
        print('ERROR: No meaningful content', file=sys.stderr)
        sys.exit(1)
    print(best)
except Exception as e:
    for field in ['content', 'reasoning_content']:
        m = re.search(r'\"' + field + r'\":\"(.*?)(?:\",\"|\"})', raw, re.DOTALL)
        if m and len(m.group(1)) > 200:
            text = m.group(1).replace('\\\\n', '\n').replace('\\\\t', '\t').replace('\\\\\"', '\"')
            print(text)
            sys.exit(0)
    print(f'ERROR: Parse failed: {e}', file=sys.stderr)
    sys.exit(1)
" > "$OUTPUT_FILE"

echo "Response saved to $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") lines)" >&2
