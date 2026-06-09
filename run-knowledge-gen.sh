#!/usr/bin/env bash
# Serial knowledge-eval generation driver (single-judge comparison runs).
# Mirrors the Q4/ai-infer3 run exactly: same canonical chunks, same
# run-chunk-validated.sh anti-cache wrapper, ABSOLUTE output paths, visible
# per-chunk status. Args:
#   $1 = model dir under results/ (e.g. gemma4-12b-q8-ai-infer2)
#   $2 = model name (e.g. gemma4-12b)
#   $3 = base url (e.g. http://192.168.2.171:8001)
set -uo pipefail
ROOT="/home/lars/source/llm-evals"
MODEL_DIR="$ROOT/results/$1"
MODEL_NAME="$2"
URL="$3/v1/chat/completions"
KEY="${LLAMA_API_KEY:-}"
OUT="$MODEL_DIR/run1"
mkdir -p "$OUT"

echo "=== GEN $MODEL_NAME @ $URL → $OUT ==="
for c in 1 2 3 4 5 6 7 8 9; do
  CHUNK=$(ls "$MODEL_DIR"/chunks/chunk${c}-*.txt)
  OUTFILE="$OUT/chunk${c}-response.txt"
  echo ">>> chunk$c  ($(basename "$CHUNK")) → $OUTFILE"
  if bash "$ROOT/run-chunk-validated.sh" "$CHUNK" "$OUTFILE" "$URL" "$KEY" "$MODEL_NAME"; then
    echo "<<< chunk$c OK ($(wc -l <"$OUTFILE") lines, $(wc -c <"$OUTFILE") bytes)"
  else
    echo "<<< chunk$c FAILED"
  fi
done
echo "=== DONE $MODEL_NAME ($(ls "$OUT"/chunk*-response.txt 2>/dev/null | wc -l)/9 chunks) ==="
