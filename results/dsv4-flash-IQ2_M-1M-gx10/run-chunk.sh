#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-validated.sh" \
  "$1" "$2" \
  "http://192.168.2.173:30000/v1/chat/completions" \
  "none" \
  "dsv4-flash"
