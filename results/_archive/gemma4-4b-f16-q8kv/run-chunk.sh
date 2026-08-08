#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-validated.sh" \
  "$1" "$2" \
  "http://192.168.2.170:8001/v1/chat/completions" \
  "${API_KEY:?set the API_KEY environment variable}" \
  "gemma4-4b"
