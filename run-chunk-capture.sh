#!/usr/bin/env bash
# Capture run-chunk: nonce anti-cache + write the raw response ALWAYS (no
# strict ID-prefix validation). For models that don't label every answer with
# the exact question ID (e.g. Mistral); the Opus judges match by content.
set -euo pipefail
CHUNK_FILE="$1"; OUTPUT_FILE="$2"; API_URL="$3"; API_KEY="$4"; MODEL_NAME="$5"
ALL_SECTIONS=$( (grep -oP '^## \K[^(]+' "$CHUNK_FILE" || true) | sed 's/ *$//' | paste -sd '/' - )
TOTAL_Q=$(grep -cP '^[A-Z]{1,3}[0-9]+ —' "$CHUNK_FILE" || true)
[[ ${TOTAL_Q:-0} -eq 0 ]] && TOTAL_Q=$(( $(grep -cP '^## \K[A-Z]{1,3}[0-9]+' "$CHUNK_FILE" || true) * 3 ))
: "${ALL_SECTIONS:=General}" "${TOTAL_Q:=30}"
PROMPT=$(cat "$CHUNK_FILE")
NONCE="eval-$(date +%s%N)-$$-${RANDOM}"
PAYLOAD=$(jq -n --arg content "$PROMPT" --arg model "$MODEL_NAME" --arg nonce "$NONCE" --arg sections "$ALL_SECTIONS" --arg total "$TOTAL_Q" \
  '{"model":$model,"messages":[{"role":"system","content":("SESSION=" + $nonce + "\nYou are a senior infrastructure and software engineer.\nTOPICS: " + $sections + "\nAnswer ALL " + $total + " questions in the user message, labeling each answer with its question ID (e.g. N1, K3, DN5). Do not skip any section.")},{"role":"user","content":$content}],"temperature":0.1,"top_p":0.95,"max_tokens":24576}')
echo "Sending to $MODEL_NAME [nonce=$NONCE] ($ALL_SECTIONS)..." >&2
RESPONSE=$(curl -s --max-time 5400 "$API_URL" -H 'Content-Type: application/json' -H "Authorization: Bearer $API_KEY" -d "$PAYLOAD" 2>/dev/null)
echo "$RESPONSE" | python3 -c "
import json,sys,re
raw=sys.stdin.read(); cleaned=re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]','',raw)
d=json.loads(cleaned); c=d['choices'][0]['message'].get('content','') or ''
if len(c)<100: print('ERROR: too short '+str(len(c)),file=sys.stderr); sys.exit(1)
open('$OUTPUT_FILE','w').write(c); print('wrote '+str(len(c))+' chars to $OUTPUT_FILE',file=sys.stderr)
" || { echo "ERROR" > "$OUTPUT_FILE"; exit 1; }
