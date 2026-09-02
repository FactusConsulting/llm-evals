#!/usr/bin/env bash
# Run all 5 evaluation passes for gemma4-4b (9 chunks each = 45 total requests)
# Sequential — uses one slot on ai-infer1, leaving the other for real work.
# 60s gap between chunks to not monopolize the server.
set -euo pipefail
cd "$(dirname "$0")"

CHUNKS=(
  chunk1-networking-linux.txt
  chunk2-k8s-dev.txt
  chunk3-opentofu-ansible.txt
  chunk4-go-rust.txt
  chunk5-dotnet-python.txt
  chunk6-js-bash-powershell.txt
  chunk7-apparch-onprem.txt
  chunk8-cloud-ot.txt
  chunk9-scenarios.txt
)

DELAY_BETWEEN=60   # seconds between chunk requests

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a run.log; }

log "Starting gemma4-4b evaluation — 5 runs × 9 chunks = 45 requests"
log "Delay between chunks: ${DELAY_BETWEEN}s"

for run in 1 2 3 4 5; do
  run_dir="run${run}"
  mkdir -p "$run_dir"
  log ""
  log "=== Run ${run}/5 ==="

  first_chunk=1
  for ((i=0; i<${#CHUNKS[@]}; i++)); do
    chunk="${CHUNKS[$i]}"
    chunk_num=$((i + 1))
    output="${run_dir}/chunk${chunk_num}-response.txt"

    if [[ -f "$output" && -s "$output" ]] && ! grep -q "^ERROR" "$output"; then
      log "  Chunk ${chunk_num} already done — skipping"
      continue
    fi

    if [[ "$first_chunk" -eq 0 ]]; then
      log "  Waiting ${DELAY_BETWEEN}s..."
      sleep "$DELAY_BETWEEN"
    fi

    log "  Chunk ${chunk_num}/${#CHUNKS[@]}: ${chunk}"
    if ./run-chunk.sh "chunks/${chunk}" "$output" 2>>"run.log"; then
      log "  Chunk ${chunk_num} OK ($(wc -l < "$output") lines)"
    else
      log "  Chunk ${chunk_num} FAILED"
    fi
    first_chunk=0
  done

  log "Run ${run} complete"
done

log ""
log "All 45 chunk requests done. Results in run1/ through run5/"
log "Next: score with Opus 4.6 judge (see ../../evaluate-chunk.py)"
