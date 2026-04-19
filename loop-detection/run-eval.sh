#!/usr/bin/env bash
# Loop Detection Eval Runner
# Sends each prompt to a local inference API and saves the response.
# Optionally runs automated spiral detection checks on the response.
#
# Usage:
#   ./run-eval.sh --model-url http://192.168.2.170:8001 --model-name qwen35-27b
#   ./run-eval.sh --model-url http://192.168.2.171:8001 --model-name qwen35-9b --scenario LD3
#   ./run-eval.sh --model-url http://192.168.2.170:8001 --model-name qwen35-27b --judge-url http://192.168.2.170:8000
#
# Outputs:
#   results/<model-name>/<scenario>-response.txt  — raw model response
#   results/<model-name>/<scenario>-score.json    — automated score (spiral flags + word count)
#
set -euo pipefail
cd "$(dirname "$0")"

PROMPTS_DIR="./prompts"
RESULTS_DIR="./results"

# ── Defaults ────────────────────────────────────────────────────────────────
MODEL_URL="http://192.168.2.170:8001"
MODEL_NAME=""
API_KEY="${LLAMA_API_KEY:-}"
SCENARIO=""          # If set, run only this scenario (e.g., LD3)
JUDGE_URL=""         # If set, send each response to judge for rubric scoring
VERBOSE=0
MAX_TOKENS=4096
TEMPERATURE=0.1
PARALLEL=0           # Run all scenarios in parallel (default: sequential)
DELAY_BETWEEN=0      # Seconds to sleep between scenarios (courtesy gap for shared server)

# ── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model-url)    MODEL_URL="$2";    shift 2 ;;
    --model-name)   MODEL_NAME="$2";   shift 2 ;;
    --api-key)      API_KEY="$2";      shift 2 ;;
    --scenario)     SCENARIO="$2";     shift 2 ;;
    --judge-url)    JUDGE_URL="$2";    shift 2 ;;
    --max-tokens)   MAX_TOKENS="$2";   shift 2 ;;
    --temperature)  TEMPERATURE="$2";  shift 2 ;;
    --parallel)     PARALLEL=1;        shift ;;
    --delay-between) DELAY_BETWEEN="$2"; shift 2 ;;
    --verbose|-v)   VERBOSE=1;         shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$MODEL_NAME" ]]; then
  echo "ERROR: --model-name is required"
  exit 1
fi

# ── Helper: call the inference API ─────────────────────────────────────────
call_model() {
  local prompt_file="$1"
  local output_file="$2"
  local prompt
  prompt=$(cat "$prompt_file")

  # Build JSON payload
  local payload
  payload=$(python3 -c "
import json, sys
prompt = sys.stdin.read()
payload = {
    'model': '$MODEL_NAME',
    'messages': [
        {
            'role': 'system',
            'content': (
                'You are an expert systems engineer and software developer acting as an agentic worker. '
                'Complete the task given to you. Follow all explicit constraints in the prompt. '
                'Do not add explanatory sections after you have finished the task. '
                'Do not repeat conclusions you have already stated.'
            )
        },
        {
            'role': 'user',
            'content': prompt
        }
    ],
    'max_tokens': $MAX_TOKENS,
    'temperature': $TEMPERATURE,
}
print(json.dumps(payload))
" <<< "$prompt")

  local auth_header=""
  if [[ -n "$API_KEY" ]]; then
    auth_header="-H \"Authorization: Bearer ${API_KEY}\""
  fi

  local response
  response=$(curl -s \
    -X POST "${MODEL_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    ${API_KEY:+-H "Authorization: Bearer ${API_KEY}"} \
    -d "$payload" \
    --max-time 600)

  # Extract content from response
  python3 -c "
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
    content = data['choices'][0]['message'].get('content') or data['choices'][0]['message'].get('reasoning_content', '')
    print(content)
except Exception as e:
    print(f'ERROR parsing response: {e}', file=sys.stderr)
    print(raw[:500], file=sys.stderr)
    sys.exit(1)
" <<< "$response" > "$output_file"
}

# ── Helper: automated spiral detection ─────────────────────────────────────
check_spiral() {
  local response_file="$1"
  local scenario_id="$2"
  local score_file="$3"

  python3 - "$response_file" "$scenario_id" "$score_file" << 'PYEOF'
import sys
import json
import re
from pathlib import Path

response_file = sys.argv[1]
scenario_id = sys.argv[2]
score_file = sys.argv[3]

text = Path(response_file).read_text()
words = text.split()
word_count = len(words)

flags = []

# 1. Word count checks per scenario
word_limits = {
    "LD9": 800,
    "LD12": 300,
}
limit = word_limits.get(scenario_id)
if limit and word_count > limit:
    flags.append(f"WORD_COUNT_EXCEEDED: {word_count} words (limit {limit})")

# 2. Required terminal phrase
terminal_phrases = {
    "LD12": "RECOMMENDATION COMPLETE.",
}
required = terminal_phrases.get(scenario_id)
if required and required not in text:
    flags.append(f"MISSING_TERMINAL_PHRASE: '{required}' not found")

# 3. Paragraph repetition check (simple bigram overlap)
# Skip table-heavy paragraphs (lines mostly starting with | are structured data
# that legitimately repeats across accumulation steps, not looping prose).
accumulation_scenarios = {"LD5"}
def is_table_paragraph(p):
    lines = [l.strip() for l in p.split("\n") if l.strip()]
    if not lines:
        return False
    # Matches both leading-pipe tables (| col | col |) and pipe-separator tables
    # (col | col | col) and markdown separator rows (---|---|---)
    table_lines = sum(1 for l in lines if "|" in l or re.match(r'^[-| ]+$', l))
    return table_lines / len(lines) > 0.5

paragraphs = [
    p.strip() for p in text.split("\n\n")
    if len(p.strip()) > 100
    and not (scenario_id in accumulation_scenarios and is_table_paragraph(p.strip()))
]

def bigrams(s):
    words = s.lower().split()
    return set(zip(words, words[1:]))

spiral_para = False
for i in range(len(paragraphs)):
    for j in range(i + 1, len(paragraphs)):
        bg_i = bigrams(paragraphs[i])
        bg_j = bigrams(paragraphs[j])
        if not bg_i or not bg_j:
            continue
        overlap = len(bg_i & bg_j) / min(len(bg_i), len(bg_j))
        if overlap > 0.85:
            flags.append(f"REPEATED_PARAGRAPH: paragraphs {i+1} and {j+1} share {overlap:.0%} bigrams")
            spiral_para = True
            break
    if spiral_para:
        break

# 4. First-vs-last block overlap (re-stating the task at the end)
# Requires >500 words: on shorter responses the first/last 200-word windows
# overlap heavily by arithmetic alone, causing near-certain false positives.
if len(words) > 500:
    first_200 = set(zip(words[:200], words[1:201]))
    last_200 = set(zip(words[-200:], words[-199:]))
    if first_200 and last_200:
        overlap = len(first_200 & last_200) / min(len(first_200), len(last_200))
        if overlap > 0.60:
            flags.append(f"RECAP_DETECTED: first and last 200 words share {overlap:.0%} bigrams")

# 5. Repeated action strings (for iterative-fix scenarios)
iterative_scenarios = {"LD2", "LD6", "LD10"}
if scenario_id in iterative_scenarios:
    lines = [l.strip() for l in text.split("\n") if l.strip()]
    seen = {}
    for line in lines:
        key = re.sub(r'\s+', ' ', line.lower())
        if len(key) > 40:
            seen[key] = seen.get(key, 0) + 1
            if seen[key] >= 2:
                flags.append(f"REPEATED_ACTION: '{line[:80]}'")
                break

is_spiral = len(flags) > 0

score = {
    "scenario": scenario_id,
    "word_count": word_count,
    "spiral_flags": flags,
    "is_spiral": is_spiral,
    "auto_termination_score": 0 if is_spiral else 3,
    "note": "Dimensions Completion/Accuracy/Economy require judge evaluation"
}

Path(score_file).write_text(json.dumps(score, indent=2))
print(json.dumps(score, indent=2))
PYEOF
}

# ── Helper: judge scoring (optional) ───────────────────────────────────────
judge_score() {
  local response_file="$1"
  local scenario_id="$2"
  local score_file="$3"
  local rubric_excerpt

  # Extract the relevant rubric section for this scenario
  rubric_excerpt=$(python3 -c "
import re, sys
rubric = open('rubric.md').read()
# Find the section for this scenario
pattern = r'### ${scenario_id}.*?(?=### LD|\Z)'
m = re.search(pattern, rubric, re.DOTALL)
if m:
    print(m.group(0)[:2000])
else:
    print('Rubric section not found for ${scenario_id}')
")

  local response
  response=$(cat "$response_file")

  local payload
  payload=$(python3 -c "
import json, sys
rubric = sys.argv[1]
response = sys.argv[2]
scenario_id = sys.argv[3]

judge_prompt = f'''You are evaluating a model response for loop/spiral tendency. Score it on the following dimensions:

Rubric for {scenario_id}:
{rubric}

Model response:
{response[:6000]}

Score the response on:
1. Completion (0-4): Did it produce the required deliverable?
2. Accuracy (0-2): Is the substance correct?
3. Economy (0-1): Concise, no padding?

The Termination score (0-3) has already been set by automated checks.

Respond ONLY with JSON in this exact format:
{{
  \"completion\": <0-4>,
  \"accuracy\": <0-2>,
  \"economy\": <0-1>,
  \"verdict\": \"pass|partial|spiral\",
  \"brief_justification\": \"<1-2 sentences>\"
}}'''

payload = {
    'model': '$MODEL_NAME',
    'messages': [
        {'role': 'system', 'content': 'You are a strict evaluator of LLM responses. Respond with pure JSON only.'},
        {'role': 'user', 'content': judge_prompt}
    ],
    'max_tokens': 512,
    'temperature': 0.0,
}
print(json.dumps(payload))
" "$rubric_excerpt" "$response" "$scenario_id")

  local judge_response
  judge_response=$(curl -s \
    -X POST "${JUDGE_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    ${API_KEY:+-H "Authorization: Bearer ${API_KEY}"} \
    -d "$payload" \
    --max-time 120)

  python3 -c "
import json, sys

raw = sys.stdin.read()
score_file = sys.argv[1]
scenario_id = sys.argv[2]

try:
    data = json.loads(raw)
    content = data['choices'][0]['message'].get('content', '')
    # Strip markdown fencing if present
    content = content.strip().lstrip('\`\`\`json').rstrip('\`\`\`').strip()
    judge = json.loads(content)
except Exception as e:
    print(f'WARNING: Could not parse judge response: {e}', file=sys.stderr)
    judge = {}

# Merge with existing score file
existing = json.loads(open(score_file).read())
existing['judge'] = judge
existing['total_score'] = (
    existing.get('auto_termination_score', 0) +
    judge.get('completion', 0) +
    judge.get('accuracy', 0) +
    judge.get('economy', 0)
)
open(score_file, 'w').write(json.dumps(existing, indent=2))
print(json.dumps(existing, indent=2))
" "$score_file" "$scenario_id" <<< "$judge_response"
}

# ── Main: collect scenarios to run ─────────────────────────────────────────
if [[ -n "$SCENARIO" ]]; then
  prompt_files=("${PROMPTS_DIR}/${SCENARIO}-"*.txt)
  if [[ ! -f "${prompt_files[0]}" ]]; then
    echo "ERROR: No prompt found for scenario $SCENARIO"
    exit 1
  fi
else
  mapfile -t prompt_files < <(ls "${PROMPTS_DIR}"/LD*.txt 2>/dev/null | sort)
fi

if [[ ${#prompt_files[@]} -eq 0 ]]; then
  echo "ERROR: No prompt files found in ${PROMPTS_DIR}/"
  exit 1
fi

output_dir="${RESULTS_DIR}/${MODEL_NAME}"
mkdir -p "$output_dir"

timestamp=$(date +%Y%m%d-%H%M%S)

echo "============================================================"
echo "  Loop Detection Eval"
echo "  Model:      $MODEL_NAME"
echo "  API:        $MODEL_URL"
echo "  Scenarios:  ${#prompt_files[@]}"
echo "  Timestamp:  $timestamp"
[[ -n "$JUDGE_URL" ]] && echo "  Judge:      $JUDGE_URL"
echo "============================================================"
echo ""

# ── Run scenarios ───────────────────────────────────────────────────────────
run_scenario() {
  local prompt_file="$1"
  local filename
  filename=$(basename "$prompt_file" .txt)
  local scenario_id
  scenario_id=$(echo "$filename" | grep -oP '^LD\d+')

  local response_file="${output_dir}/${filename}-${timestamp}-response.txt"
  local score_file="${output_dir}/${filename}-${timestamp}-score.json"

  echo "--- ${scenario_id}: ${filename} ---"

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "  Sending prompt ($(wc -w < "$prompt_file") words)..."
  fi

  call_model "$prompt_file" "$response_file"
  local word_count
  word_count=$(wc -w < "$response_file")
  echo "  Response: ${word_count} words -> $response_file"

  check_spiral "$response_file" "$scenario_id" "$score_file" > /dev/null
  local spiral_flags
  spiral_flags=$(python3 -c "
import json
s = json.load(open('$score_file'))
flags = s.get('spiral_flags', [])
print(f'  Auto flags: {len(flags)} {\"(\" + flags[0][:60] + \"...\" if flags else \"\"}')
")
  echo "$spiral_flags"

  if [[ -n "$JUDGE_URL" ]]; then
    echo "  Running judge scoring..."
    judge_score "$response_file" "$scenario_id" "$score_file" > /dev/null
    local total
    total=$(python3 -c "import json; s=json.load(open('$score_file')); print(s.get('total_score','?'))")
    echo "  Judge score: ${total}/10"
  fi

  echo ""
}

if [[ "$PARALLEL" -eq 1 ]]; then
  pids=()
  for prompt_file in "${prompt_files[@]}"; do
    run_scenario "$prompt_file" &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
else
  first=1
  for prompt_file in "${prompt_files[@]}"; do
    if [[ "$first" -eq 0 && "$DELAY_BETWEEN" -gt 0 ]]; then
      echo "  (waiting ${DELAY_BETWEEN}s before next scenario...)"
      sleep "$DELAY_BETWEEN"
    fi
    run_scenario "$prompt_file"
    first=0
  done
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  SUMMARY"
echo "============================================================"

python3 - "$output_dir" "$timestamp" << 'PYEOF'
import json
import sys
from pathlib import Path

output_dir = Path(sys.argv[1])
timestamp = sys.argv[2]

score_files = sorted(output_dir.glob(f"*-{timestamp}-score.json"))

if not score_files:
    print("  No score files found.")
    sys.exit(0)

total_auto = 0
total_judge = 0
has_judge = False
spirals = 0

for sf in score_files:
    s = json.loads(sf.read_text())
    scenario = s.get("scenario", "?")
    wc = s.get("word_count", "?")
    flags = s.get("spiral_flags", [])
    auto_term = s.get("auto_termination_score", "?")
    is_spiral = s.get("is_spiral", False)
    judge = s.get("judge", {})
    total = s.get("total_score")

    if is_spiral:
        spirals += 1

    verdict = judge.get("verdict", "?") if judge else "unscored"
    total_str = f"{total}/10" if total is not None else "?/10"

    flag_str = f" [{len(flags)} flags]" if flags else ""
    spiral_str = " SPIRAL" if is_spiral else ""
    print(f"  {scenario}: {total_str}  {verdict}{spiral_str}{flag_str}  ({wc} words)")

    if isinstance(auto_term, int):
        total_auto += auto_term
    if total is not None:
        total_judge += total
        has_judge = True

print("")
print(f"  Spiral count: {spirals}/{len(score_files)}")
if has_judge:
    max_possible = len(score_files) * 10
    pct = 100 * total_judge / max_possible if max_possible > 0 else 0
    print(f"  Total score:  {total_judge}/{max_possible} ({pct:.1f}%)")
    if pct >= 90:
        interpretation = "STABLE — suitable for production agentic tasks"
    elif pct >= 70:
        interpretation = "MINOR LOOPING — monitor in production, tune samplers"
    elif pct >= 50:
        interpretation = "SIGNIFICANT LOOPING RISK — requires DRY sampler or n_predict cap"
    else:
        interpretation = "HIGH LOOPING RISK — not suitable for open-ended agentic tasks"
    print(f"  Verdict:      {interpretation}")
else:
    print("  (Run with --judge-url to get full scores)")

print("")
PYEOF

echo "  Results dir: ${output_dir}/"
echo "============================================================"
