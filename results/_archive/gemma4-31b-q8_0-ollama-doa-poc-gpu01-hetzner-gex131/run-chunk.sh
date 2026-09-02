#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-validated.sh" \
  "$1" "$2" \
  "http://23.88.29.100:11434/v1/chat/completions" \
  "" \
  "gemma4:31b-q8_0"
