#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-validated.sh" \
  "$1" "$2" \
  "http://192.168.2.170:8001/v1/chat/completions" \
  "63a83819062c0946e9907b257b234be96cec03ea0fb388db716e95558ccf630d" \
  "gemma4-4b"
