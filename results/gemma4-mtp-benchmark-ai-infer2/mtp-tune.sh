#!/usr/bin/env bash
# MTP nmax sweep for one model. Usage: mtp-tune.sh <NAME> <BASE> <ASSIST> <CTX> <NMAX_LIST...>
NAME="$1"; BASE="$2"; ASSIST="$3"; CTX="${4:-16384}"; shift 4; NMAX_LIST="$*"
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
  local label="$1"; shift
  "$BIN" -m "$BASE" -ngl 999 --tensor-split 1,1 -c "$CTX" -fa on -np 1 \
     --host 127.0.0.1 --port "$PORT" "$@" > /tmp/srv-tune.log 2>&1 &
  local srv=$! up=0 i
  for i in $(seq 1 90); do curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { up=1; break; }; sleep 2; done
  if [ "$up" != 1 ]; then echo "  [$label] server kom ikke op:"; tail -4 /tmp/srv-tune.log|sed 's/^/    /'; kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; PHASE_TPS=""; return 1; fi
  local sum=0 cnt=0 accsum=0 acccnt=0 p body resp parsed tps acc
  for p in "${PROMPTS[@]}"; do
    body=$(python3 -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1],"n_predict":192,"temperature":1.0,"top_p":0.95,"top_k":64,"cache_prompt":False}))' "$p")
    resp=$(curl -s "http://127.0.0.1:$PORT/completion" -H 'Content-Type: application/json' -d "$body")
    parsed=$(printf '%s' "$resp" | python3 -c 'import json,sys
try:
 t=json.load(sys.stdin).get("timings",{}); dn=t.get("draft_n",0) or 0; da=t.get("draft_n_accepted",0) or 0
 print(round(t.get("predicted_per_second",0) or 0,1), round(da/dn,3) if dn else -1)
except Exception: print(0,-1)')
    tps=$(echo "$parsed"|awk '{print $1}'); acc=$(echo "$parsed"|awk '{print $2}')
    sum=$(python3 -c "print($sum+$tps)"); cnt=$((cnt+1))
    [ "$acc" != "-1" ] && { accsum=$(python3 -c "print($accsum+$acc)"); acccnt=$((acccnt+1)); }
  done
  kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null; sleep 2
  PHASE_TPS=$(python3 -c "print(round($sum/$cnt,1) if $cnt else 0)")
  PHASE_ACC=$(python3 -c "print(round($accsum/$acccnt,3) if $acccnt else 'n/a')")
}
echo "===================== $NAME — nmax sweep ====================="
run_phase "baseline"
BASE_TPS="${PHASE_TPS:-0}"
echo "  baseline (ingen MTP): ${BASE_TPS} tok/s"
for n in $NMAX_LIST; do
  run_phase "mtp n=$n" --model-draft "$ASSIST" --spec-type draft-mtp --spec-draft-n-max "$n"
  sp=$(python3 -c "print(round(${PHASE_TPS:-0}/$BASE_TPS,2) if $BASE_TPS else 0)")
  printf "  n-max=%-2s : %-6s tok/s  (%sx)  acc=%s\n" "$n" "${PHASE_TPS:-ERR}" "$sp" "$PHASE_ACC"
done
sudo systemctl start llama-server 2>/dev/null
