#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-validated.sh" \
  "$1" "$2" \
  "http://192.168.2.171:8001/v1/chat/completions" \
  "17e08dbd3a3b9f30db4c1f32959e6f9858a4ca9c7d8f485ee0c25a27f54af902" \
  "gemma4-26b"
