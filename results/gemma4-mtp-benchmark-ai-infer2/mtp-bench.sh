#!/usr/bin/env bash
# MTP before/after token-production benchmark (one model), via llama-server /completion.
# Usage: mtp-bench.sh <NAME> <BASE_GGUF> <ASSISTANT_GGUF> <NMAX> <CTX>
NAME="$1"; BASE="$2"; ASSIST="$3"; NMAX="${4:-4}"; CTX="${5:-16384}"
BIN=/opt/llama.cpp-mtp/build/bin/llama-server
PORT=8090
sudo systemctl stop llama-server 2>/dev/null; sleep 3

PROMPTS=(
  "Write a complete, runnable Python implementation of a thread-safe LRU cache class with get and put methods."
  "Explain in detail how the Raft consensus algorithm achieves distributed consensus, covering leader election and log replication."
  "Solve step by step: a train travels 120 km in 1.5 hours, then 200 km in 2 hours. Compute the average speed for the whole trip."
  "Summarize the key trade-offs between optimistic and pessimistic concurrency control in databases."
)

PHASE_TPS=""; PHASE_ACC="n/a"
run_phase() {
  local tag="$1" label="$2"; shift 2
  local log="/tmp/srv-${tag}.log"
  "$BIN" -m "$BASE" -ngl 999 --tensor-split 1,1 -c "$CTX" -fa on -np 1 \
     --host 127.0.0.1 --port "$PORT" "$@" > "$log" 2>&1 &
  local srv=$!
  local up=0 i
  for i in $(seq 1 90); do
    curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { up=1; break; }
    sleep 2
  done
  if [ "$up" != 1 ]; then
    echo "  [$label] server kom ikke op:"; tail -n 6 "$log" | sed 's/^/    /'
    kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; PHASE_TPS=""; return 1
  fi
  echo "  --- $label ---"
  local sum=0 cnt=0 accsum=0 acccnt=0 p body resp parsed tps acc accdisp
  for p in "${PROMPTS[@]}"; do
    body=$(python3 -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1],"n_predict":192,"temperature":1.0,"top_p":0.95,"top_k":64,"cache_prompt":False}))' "$p")
    resp=$(curl -s "http://127.0.0.1:$PORT/completion" -H 'Content-Type: application/json' -d "$body")
    parsed=$(printf '%s' "$resp" | python3 -c '
import json,sys
try:
  t=json.load(sys.stdin).get("timings",{})
  tps=t.get("predicted_per_second",0) or 0
  dn=t.get("draft_n",0) or 0; da=t.get("draft_n_accepted",0) or 0
  print(round(tps,1), round(da/dn,3) if dn else -1)
except Exception:
  print(0,-1)
')
    tps=$(echo "$parsed" | awk '{print $1}'); acc=$(echo "$parsed" | awk '{print $2}')
    accdisp="n/a"; [ "$acc" != "-1" ] && accdisp="$acc"
    printf "    %-9s tok/s=%-7s acc=%s\n" "$(echo "$p" | cut -c1-9)" "$tps" "$accdisp"
    sum=$(python3 -c "print($sum+$tps)"); cnt=$((cnt+1))
    [ "$acc" != "-1" ] && { accsum=$(python3 -c "print($accsum+$acc)"); acccnt=$((acccnt+1)); }
  done
  kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; sleep 2
  PHASE_TPS=$(python3 -c "print(round($sum/$cnt,1) if $cnt else 0)")
  PHASE_ACC=$(python3 -c "print(round($accsum/$acccnt,3) if $acccnt else 'n/a')")
  echo "  [$label] GENNEMSNIT: ${PHASE_TPS} tok/s, acceptance ${PHASE_ACC}"
}

echo "===================== $NAME ====================="
run_phase before "FOER (baseline)"
B_TPS="${PHASE_TPS:-0}"
run_phase after "EFTER (MTP)" --model-draft "$ASSIST" --spec-type draft-mtp --spec-draft-n-max "$NMAX"
M_TPS="${PHASE_TPS:-0}"; M_ACC="${PHASE_ACC:-n/a}"
echo ""
echo "  >>> $NAME: ${B_TPS} -> ${M_TPS} tok/s  (speedup $(python3 -c "print(round($M_TPS/$B_TPS,2) if float('$B_TPS' or 0) else 'n/a')")x, acceptance ${M_ACC})"
sudo systemctl start llama-server 2>/dev/null
