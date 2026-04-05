#!/usr/bin/env bash
set -euo pipefail
CHUNK_FILE="$1"
OUTPUT_FILE="$2"
API_KEY="3960bd38560adb401e986c5ad15e5ca3c7bc1aa7864297d0dc14bcbc564cce45"
API_URL="http://192.168.2.171:8000/v1/chat/completions"

PROMPT=$(cat "$CHUNK_FILE")
PAYLOAD=$(jq -n \
  --arg content "$PROMPT" \
  '{
    "model": "qwen3.5-9b",
    "messages": [
      {"role": "system", "content": "You are a senior infrastructure and software engineer. Answer each question directly and thoroughly. Label each answer with its question ID (e.g., N1, L5, G3). Be concise but complete."},
      {"role": "user", "content": $content}
    ],
    "temperature": 0.1,
    "top_p": 0.95,
    "max_tokens": 24576
  }')

echo "Sending chunk to qwen3.5-9b (vLLM)..." >&2
START=$(date +%s)
RESPONSE=$(curl -s --max-time 1800 "$API_URL" \
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
    reasoning = msg.get('reasoning_content', '') or msg.get('reasoning', '') or ''
    # Use content if substantial; fall back to reasoning (thinking model mid-stream)
    best = content if len(content) > 100 else reasoning
    if len(best) < 100:
        print('ERROR: No meaningful content', file=sys.stderr)
        print(raw[:500], file=sys.stderr)
        sys.exit(1)
    print(best)
except Exception as e:
    print(f'ERROR: Parse failed: {e}', file=sys.stderr)
    print(raw[:500], file=sys.stderr)
    sys.exit(1)
" > "$OUTPUT_FILE"

echo "Response saved to $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") lines)" >&2
