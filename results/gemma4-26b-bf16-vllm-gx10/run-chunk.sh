#!/usr/bin/env bash
set -euo pipefail
CHUNK_FILE="$1"; OUTPUT_FILE="$2"
API_KEY="${API_KEY:?set API_KEY}"
API_URL="http://192.168.2.173:8000/v1/chat/completions"
PROMPT=$(cat "$CHUNK_FILE")
PAYLOAD=$(jq -n --arg content "$PROMPT" '{
  "model":"gemma4-26b",
  "messages":[
    {"role":"system","content":"You are a senior infrastructure and software engineer. Answer each question directly and thoroughly. Label each answer with its question ID (e.g., N1, L5, G3). Be concise but complete."},
    {"role":"user","content":$content}],
  "temperature":0.1,"top_p":0.95,"max_tokens":24576}')
START=$(date +%s)
RESPONSE=$(curl -s --max-time 2400 "$API_URL" -H 'Content-Type: application/json' -H "Authorization: Bearer $API_KEY" -d "$PAYLOAD" 2>/dev/null)
END=$(date +%s); echo "Chunk completed in $((END-START))s" >&2
echo "$RESPONSE" | python3 -c "
import json,sys,re
raw=sys.stdin.read(); cleaned=re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]','',raw)
try:
    d=json.loads(cleaned); msg=d['choices'][0]['message']
    content=msg.get('content','') or ''
    reasoning=(msg.get('reasoning') or msg.get('reasoning_content') or '')
    best=content if len(content)>200 else reasoning
    if len(best)<100: best='ERROR: short/empty response\n'+content[:500]+reasoning[:500]
    print(best)
except Exception as e:
    print('ERROR:',e); print(cleaned[:1000])
" > "$OUTPUT_FILE"
