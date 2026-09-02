#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
: "${API_KEY:?set API_KEY}"
CHUNKS=(chunk1-networking-linux.txt chunk2-k8s-dev.txt chunk3-opentofu-ansible.txt chunk4-go-rust.txt chunk5-dotnet-python.txt chunk6-js-bash-powershell.txt chunk7-apparch-onprem.txt chunk8-cloud-ot.txt chunk9-scenarios.txt)
for run in 1 2 3; do
  rd="run${run}"; mkdir -p "$rd"
  for ((i=0;i<${#CHUNKS[@]};i++)); do n=$((i+1)); out="${rd}/chunk${n}-response.txt"
    if [[ -s "$out" ]] && ! grep -q ERROR "$out"; then echo "KN run${run} chunk${n}: skip"; continue; fi
    echo "KN run${run} chunk${n}: START $(date +%H:%M:%S)"
    ./run-chunk.sh "chunks/${CHUNKS[$i]}" "$out" || echo "KN run${run} chunk${n}: FAILED"
    echo "KN run${run} chunk${n}: DONE $(wc -l < "$out" 2>/dev/null) lines, $(wc -c < "$out" 2>/dev/null) bytes"
  done
done
echo "KNOWLEDGE-ALL-DONE"
