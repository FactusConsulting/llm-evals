#!/bin/bash
set -euo pipefail
cd /home/lars/source/llm-evals/results/qwen35-27b-opus-distilled-q4km
API_KEY="${API_KEY:?set the API_KEY environment variable}"
API_URL="http://192.168.2.170:8001/v1/chat/completions"

mkdir -p run1/splits

for f in splits/chunk*.txt; do
  name=$(basename "$f" .txt)
  out="run1/splits/${name}-response.txt"
  
  if [[ -f "$out" ]] && [[ -s "$out" ]] && ! head -1 "$out" | grep -q "Let me work\|ERROR"; then
    echo "[$(date +%H:%M:%S)] $name: already done, skipping"
    continue
  fi
  
  echo "[$(date +%H:%M:%S)] $name: sending..."
  PROMPT=$(cat "$f")
  PAYLOAD=$(jq -n --arg content "$PROMPT" '{
    "model": "qwen3.5-27b-opus",
    "messages": [
      {"role": "system", "content": "You are a senior infrastructure and software engineer. Answer each question directly and thoroughly. Label each answer with its question ID. Be concise but complete."},
      {"role": "user", "content": $content}
    ],
    "temperature": 0.1,
    "top_p": 0.95,
    "max_tokens": 8192
  }')
  
  RESPONSE=$(curl -s --max-time 600 "$API_URL"     -H "Content-Type: application/json"     -H "Authorization: Bearer $API_KEY"     -d "$PAYLOAD" 2>/dev/null)
  
  echo "$RESPONSE" | python3 -c "
import json, sys, re
raw = sys.stdin.read()
cleaned = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]', '', raw)
try:
    d = json.loads(cleaned)
    msg = d['choices'][0]['message']
    content = msg.get('content', '') or ''
    reasoning = msg.get('reasoning_content', '') or ''
    best = content if len(content) > 100 else reasoning
    if len(best) < 50:
        print('ERROR: No meaningful content', file=sys.stderr)
        sys.exit(1)
    print(best)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" > "$out" 2>&1
  
  lines=$(wc -l < "$out")
  first=$(head -1 "$out" | cut -c1-60)
  echo "[$(date +%H:%M:%S)] $name: $lines lines — $first"
done

echo "[$(date +%H:%M:%S)] ALL SPLITS COMPLETE"
