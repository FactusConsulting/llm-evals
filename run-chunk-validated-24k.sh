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

# Extract ALL section headers (not just the first), all question ID prefixes,
# and the total question count. The old version only grabbed the first `## `
# header which caused a real bug: on chunks like chunk1 (Networking+Linux) or
# chunk4 (Go+Rust), the system prompt told the model "TOPIC: Go (20 questions)"
# even though the chunk had 40 questions. The model intermittently (40% hit
# rate at temp 0.1) honored the "20 questions" hint literally and stopped
# after the first sub-topic, silently dropping half the answers.
# Two chunk formats exist:
#   (a) knowledge chunks: `^N1 — Easy: ...` style questions under `## Networking (20 questions)` headers
#   (b) scenario chunks (chunk9): `^## SC1 — ...` headers with `Part A/B/C` prompts inside
# We detect both by trying format (a) first and falling back to (b).
# Use `|| true` on every grep — with `set -euo pipefail`, an empty match
# would otherwise abort the whole script silently when piped through tail.
ALL_SECTIONS=$( (grep -oP '^## \K[^(]+' "$CHUNK_FILE" || true) | sed 's/ *$//' | paste -sd '/' - )
TOTAL_Q=$(grep -cP '^[A-Z]{1,3}[0-9]+ —' "$CHUNK_FILE" || true)
EXPECTED_IDS=$( (grep -oP '^[A-Z]{1,3}(?=[0-9]+ —)' "$CHUNK_FILE" || true) | sort -u | tr '\n' '|' | sed 's/|$//')
FIRST_ID=$( (grep -oP '^[A-Z]{1,3}[0-9]+' "$CHUNK_FILE" || true) | head -1)
if [[ ${TOTAL_Q:-0} -eq 0 ]]; then
  # Scenario format: headers like `## SC1 — ...`, each with Parts A/B/C
  SCENARIO_IDS=$(grep -oP '^## \K[A-Z]{1,3}[0-9]+' "$CHUNK_FILE")
  SCENARIO_COUNT=$(echo "$SCENARIO_IDS" | grep -c . || true)
  PART_COUNT=$(grep -cP '^Part [A-Z]:' "$CHUNK_FILE" || true)
  TOTAL_Q=$(( SCENARIO_COUNT * 3 ))  # assume 3 parts per scenario if Part grep fails
  [[ $PART_COUNT -gt 0 ]] && TOTAL_Q=$PART_COUNT
  EXPECTED_IDS=$(echo "$SCENARIO_IDS" | grep -oP '^[A-Z]{1,3}' | sort -u | tr '\n' '|' | sed 's/|$//')
  FIRST_ID=$(echo "$SCENARIO_IDS" | head -1)
  ALL_SECTIONS="Scenarios (${SCENARIO_COUNT} × A/B/C parts)"
fi
: "${ALL_SECTIONS:=General}" "${TOTAL_Q:=0}" "${EXPECTED_IDS:=SC}" "${FIRST_ID:=SC1}"

echo "Topics: $ALL_SECTIONS | Total: $TOTAL_Q | Expected prefixes: $EXPECTED_IDS (first: $FIRST_ID)" >&2

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
    --arg sections "$ALL_SECTIONS" \
    --arg total "$TOTAL_Q" \
    '{
      "model": $model,
      "messages": [
        {"role": "system", "content": ("SESSION=" + $nonce + "\nYou are a senior infrastructure and software engineer.\nTOPICS: " + $sections + "\nAnswer ALL " + $total + " questions in the user message, labeling each answer with its question ID. Do not skip any section.")},
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

  # Validate: every expected ID prefix must appear at least 3 times. This
  # catches silent section-truncation where the model only answers the first
  # sub-topic of a multi-section chunk (see root cause in header comment).
  MATCH_COUNT=$(echo "$CONTENT" | grep -coP "($EXPECTED_IDS)[0-9]" || true)
  MIN_PER_SECTION=999
  MISSING_SECTIONS=""
  for prefix in $(echo "$EXPECTED_IDS" | tr '|' ' '); do
    c=$(echo "$CONTENT" | grep -coP "\b${prefix}[0-9]+" || true)
    if [[ $c -lt 3 ]]; then
      MISSING_SECTIONS+="${prefix}($c) "
    fi
    if [[ $c -lt $MIN_PER_SECTION ]]; then
      MIN_PER_SECTION=$c
    fi
  done

  if [[ -n "$MISSING_SECTIONS" ]]; then
    echo "VALIDATION FAILED: sections below 3 matches: $MISSING_SECTIONS (total match count: $MATCH_COUNT)" >&2
    if [[ $attempt -eq $MAX_RETRIES ]]; then
      echo "GIVING UP" >&2
      exit 1
    fi
    continue
  fi

  echo "VALIDATED: $MATCH_COUNT total IDs, min-per-section=$MIN_PER_SECTION across [$EXPECTED_IDS]" >&2
  echo "$CONTENT" > "$OUTPUT_FILE"
  echo "Saved to $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") lines)" >&2
  exit 0
done
