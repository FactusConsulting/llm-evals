#!/usr/bin/env bash
# Narrow-delivery harness. For each story in stories.yaml: send the prompt to the
# model, save the response, run the story's functional grader, record
# obedience / trap_avoidance / verification. A story is DELIVERED only if the
# grader exits 0 (all three). Reports per-story + aggregate delivery rate.
#
# Usage: ./run.sh --model-url http://host:8080 --model-name <name> [--api-key K] [--out DIR]
set -uo pipefail
cd "$(dirname "$0")"

URL=""; NAME=""; KEY="dummy"; OUT="results/$(date +%Y%m%d-%H%M%S)"
while [ $# -gt 0 ]; do case "$1" in
  --model-url) URL="$2"; shift 2;; --model-name) NAME="$2"; shift 2;;
  --api-key) KEY="$2"; shift 2;; --out) OUT="$2"; shift 2;; *) echo "unknown: $1"; exit 2;; esac; done
[ -z "$URL" ] || [ -z "$NAME" ] && { echo "need --model-url and --model-name"; exit 2; }
mkdir -p "$OUT"

# emit the story list as id<TAB>grader, and write each prompt to a temp file
mapfile -t IDS < <(python3 -c "
import yaml,os
d=yaml.safe_load(open('stories.yaml'))
os.makedirs('$OUT/prompts',exist_ok=True)
for s in d['stories']:
    open(f\"$OUT/prompts/{s['id']}.txt\",'w').write(s['prompt'])
    print(s['id']+'\t'+s['grader'])
")

total=0; delivered=0; ob_sum=0; tr_sum=0; ve_sum=0
printf '%-32s %-10s %-6s %-6s %-6s\n' STORY DELIVERED obey trap verif | tee "$OUT/summary.txt"
for line in "${IDS[@]}"; do
  id="${line%%	*}"; grader="${line##*	}"
  prompt=$(cat "$OUT/prompts/$id.txt")
  # send to model (chat completions, generous tokens for thinking + output)
  body=$(python3 -c "import json,sys; print(json.dumps({'model':'$NAME','messages':[{'role':'user','content':sys.stdin.read()}],'max_tokens':16384,'temperature':0}))" <<<"$prompt")
  resp=$(curl -s --max-time 600 "$URL/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$body")
  echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message'].get('content',''))" > "$OUT/$id.response.txt" 2>/dev/null
  # grade
  gout=$(bash "$grader" "$OUT/$id.response.txt" 2>/dev/null </dev/null); rc=$?
  ob=$(echo "$gout" | grep -oE 'obedience=[01]' | cut -d= -f2); ob=${ob:-0}
  tr=$(echo "$gout" | grep -oE 'trap_avoidance=[01]' | cut -d= -f2); tr=${tr:-0}
  ve=$(echo "$gout" | grep -oE 'verification=[01]' | cut -d= -f2); ve=${ve:-0}
  dl="NO"; [ "$rc" = 0 ] && { dl="YES"; delivered=$((delivered+1)); }
  total=$((total+1)); ob_sum=$((ob_sum+ob)); tr_sum=$((tr_sum+tr)); ve_sum=$((ve_sum+ve))
  printf '%-32s %-10s %-6s %-6s %-6s\n' "$id" "$dl" "$ob" "$tr" "$ve" | tee -a "$OUT/summary.txt"
done
echo "" | tee -a "$OUT/summary.txt"
printf 'DELIVERED %d/%d (%d%%)  |  obedience %d/%d  trap-avoidance %d/%d  verification %d/%d\n' \
  "$delivered" "$total" "$((delivered*100/total))" "$ob_sum" "$total" "$tr_sum" "$total" "$ve_sum" "$total" \
  | tee -a "$OUT/summary.txt"
echo "results: $OUT"
