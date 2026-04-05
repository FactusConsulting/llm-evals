#!/usr/bin/env bash
# judge-opus.sh — Score existing loop-detection results using Claude Opus 4.6
#
# Usage:
#   ./judge-opus.sh --model-name gemma4-4b --timestamp 20260405-143830
#   ./judge-opus.sh --model-name gemma4-4b   # judges all unscored result files
#
# Requires: ANTHROPIC_API_KEY env var
#
# Reads:  results/<model-name>/<scenario>-<timestamp>-response.txt
#         results/<model-name>/<scenario>-<timestamp>-score.json  (auto scores already written)
# Writes: results/<model-name>/<scenario>-<timestamp>-score.json  (merged with judge scores)
#
set -euo pipefail
cd "$(dirname "$0")"

RESULTS_DIR="./results"
MODEL_NAME=""
TIMESTAMP=""          # Optional: filter to a specific run timestamp
JUDGE_MODEL="claude-opus-4-6"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
FORCE=0               # Re-judge even if judge scores already exist

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-name)   MODEL_NAME="$2";   shift 2 ;;
    --timestamp)    TIMESTAMP="$2";    shift 2 ;;
    --judge-model)  JUDGE_MODEL="$2";  shift 2 ;;
    --force)        FORCE=1;           shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$MODEL_NAME" ]]; then
  echo "ERROR: --model-name is required"
  exit 1
fi

if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY env var is not set"
  exit 1
fi

output_dir="${RESULTS_DIR}/${MODEL_NAME}"
if [[ ! -d "$output_dir" ]]; then
  echo "ERROR: results dir not found: $output_dir"
  exit 1
fi

# ── Find score files to judge ────────────────────────────────────────────────
if [[ -n "$TIMESTAMP" ]]; then
  mapfile -t score_files < <(ls "${output_dir}"/*-"${TIMESTAMP}"-score.json 2>/dev/null | sort)
else
  mapfile -t score_files < <(ls "${output_dir}"/*-score.json 2>/dev/null | sort)
fi

if [[ ${#score_files[@]} -eq 0 ]]; then
  echo "No score files found in ${output_dir}/"
  exit 1
fi

echo "============================================================"
echo "  Opus Judge — ${JUDGE_MODEL}"
echo "  Model under test: ${MODEL_NAME}"
echo "  Score files:      ${#score_files[@]}"
echo "============================================================"
echo ""

# ── Judge a single response file ─────────────────────────────────────────────
judge_with_opus() {
  local score_file="$1"

  # Check if already judged (skip unless --force)
  if [[ "$FORCE" -eq 0 ]]; then
    already=$(python3 -c "
import json, sys
s = json.load(open(sys.argv[1]))
print('yes' if s.get('judge') else 'no')
" "$score_file")
    if [[ "$already" == "yes" ]]; then
      echo "  [skip — already judged]"
      return
    fi
  fi

  # Derive response file path from score file path
  local response_file="${score_file/-score.json/-response.txt}"
  if [[ ! -f "$response_file" ]]; then
    echo "  WARNING: response file not found: $response_file"
    return
  fi

  local scenario_id
  scenario_id=$(basename "$score_file" | grep -oP '^LD\d+')

  # Extract rubric section for this scenario
  local rubric_excerpt
  rubric_excerpt=$(python3 -c "
import re, sys
rubric = open('rubric.md').read()
pattern = r'### ${scenario_id}.*?(?=### LD|\Z)'
m = re.search(pattern, rubric, re.DOTALL)
if m:
    print(m.group(0)[:2000])
else:
    print('No rubric section found for ${scenario_id}')
")

  local response
  response=$(cat "$response_file")

  local existing_flags
  existing_flags=$(python3 -c "
import json
s = json.load(open('${score_file}'))
flags = s.get('spiral_flags', [])
print('\\n'.join(flags) if flags else '(none)')
")

  # Build the Anthropic API request payload
  local judge_prompt
  judge_prompt=$(python3 -c "
import json, sys
scenario_id = sys.argv[1]
rubric = sys.argv[2]
response = sys.argv[3]
flags = sys.argv[4]

prompt = f'''You are evaluating a model response for loop/spiral tendency. Score it on the following dimensions.

Scenario: {scenario_id}
Rubric:
{rubric}

Automated pre-checks flagged: {flags}

Model response (truncated to 6000 chars if longer):
{response[:6000]}

Score the response on:
1. Completion (0-4): Did it produce the required deliverable?
2. Accuracy (0-2): Is the substance correct?
3. Economy (0-1): Concise, no padding?

The Termination score (0-3) is already set by automated checks; do NOT re-score it here.

If the automated flags appear to be false positives, note that in brief_justification.

Respond ONLY with valid JSON in this exact format (no markdown, no explanation outside the JSON):
{{
  \"completion\": <0-4>,
  \"accuracy\": <0-2>,
  \"economy\": <0-1>,
  \"verdict\": \"pass|partial|spiral\",
  \"brief_justification\": \"<1-2 sentences>\"
}}'''

payload = {
    'model': '${JUDGE_MODEL}',
    'max_tokens': 512,
    'messages': [
        {
            'role': 'user',
            'content': prompt
        }
    ]
}
print(json.dumps(payload))
" "$scenario_id" "$rubric_excerpt" "$response" "$existing_flags")

  local api_response
  api_response=$(curl -s \
    -X POST "https://api.anthropic.com/v1/messages" \
    -H "x-api-key: ${ANTHROPIC_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$judge_prompt" \
    --max-time 60)

  # Parse and merge into score file
  python3 -c "
import json, sys, re
from pathlib import Path

api_response = sys.argv[1]
score_file = sys.argv[2]

try:
    data = json.loads(api_response)
    content = data['content'][0]['text']
    # Strip any accidental markdown fencing
    content = re.sub(r'^[\s\`]*json\s*', '', content.strip())
    content = re.sub(r'\`+\s*\$', '', content.strip())
    judge = json.loads(content.strip())
except Exception as e:
    print(f'WARNING: Could not parse judge response: {e}', file=sys.stderr)
    print(f'Raw: {api_response[:500]}', file=sys.stderr)
    judge = {'parse_error': str(e), 'raw': api_response[:300]}

existing = json.loads(Path(score_file).read_text())
existing['judge'] = judge
existing['judge_model'] = '${JUDGE_MODEL}'
existing['total_score'] = (
    existing.get('auto_termination_score', 0) +
    judge.get('completion', 0) +
    judge.get('accuracy', 0) +
    judge.get('economy', 0)
)
Path(score_file).write_text(json.dumps(existing, indent=2))

total = existing['total_score']
verdict = judge.get('verdict', '?')
justification = judge.get('brief_justification', '')
print(f'  {total}/10  [{verdict}]  {justification}')
" "$api_response" "$score_file"
}

# ── Process each file ─────────────────────────────────────────────────────────
for score_file in "${score_files[@]}"; do
  filename=$(basename "$score_file")
  scenario_id=$(echo "$filename" | grep -oP '^LD\d+')
  echo "--- ${scenario_id}: ${filename} ---"
  judge_with_opus "$score_file"
  echo ""
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  SUMMARY — Judged by ${JUDGE_MODEL}"
echo "============================================================"

python3 - "$output_dir" "$TIMESTAMP" << 'PYEOF'
import json
import sys
from pathlib import Path

output_dir = Path(sys.argv[1])
timestamp_filter = sys.argv[2]

if timestamp_filter:
    score_files = sorted(output_dir.glob(f"*-{timestamp_filter}-score.json"))
else:
    # Group by timestamp, show latest run per scenario
    all_files = sorted(output_dir.glob("*-score.json"))
    seen = {}
    for f in all_files:
        parts = f.stem.rsplit('-', 2)
        scenario = f.stem.split('-')[0]
        seen[scenario] = f  # last one wins (sorted = chronological)
    score_files = sorted(seen.values())

total_score = 0
max_possible = 0
spirals = 0
unscored = 0

for sf in score_files:
    s = json.loads(sf.read_text())
    scenario = s.get("scenario", "?")
    wc = s.get("word_count", "?")
    is_spiral = s.get("is_spiral", False)
    judge = s.get("judge", {})
    total = s.get("total_score")
    verdict = judge.get("verdict", "unscored") if judge else "unscored"
    justification = judge.get("brief_justification", "") if judge else ""

    flag_str = f" [{len(s.get('spiral_flags',[]))} flags]" if s.get('spiral_flags') else ""
    spiral_str = " SPIRAL" if is_spiral else ""
    total_str = f"{total}/10" if total is not None else "?/10"

    print(f"  {scenario}: {total_str}  {verdict}{spiral_str}{flag_str}  ({wc} words)")
    if justification:
        print(f"         {justification}")

    if is_spiral:
        spirals += 1
    if total is not None:
        total_score += total
        max_possible += 10
    else:
        unscored += 1

print("")
print(f"  Spirals:   {spirals}/{len(score_files)}")
if max_possible > 0:
    pct = 100 * total_score / max_possible
    print(f"  Score:     {total_score}/{max_possible} ({pct:.1f}%)")
    if pct >= 90:
        verdict_str = "STABLE — suitable for production agentic tasks"
    elif pct >= 70:
        verdict_str = "MINOR LOOPING — monitor in production, tune samplers"
    elif pct >= 50:
        verdict_str = "SIGNIFICANT LOOPING RISK — requires DRY sampler or n_predict cap"
    else:
        verdict_str = "HIGH LOOPING RISK — not suitable for open-ended agentic tasks"
    print(f"  Verdict:   {verdict_str}")
if unscored:
    print(f"  Unscored:  {unscored} (judge failed to parse response)")
print("")
PYEOF

echo "  Results dir: ${output_dir}/"
echo "============================================================"
