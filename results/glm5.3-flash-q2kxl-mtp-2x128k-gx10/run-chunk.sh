#!/usr/bin/env bash
set -euo pipefail
# gx10 serves unauthenticated on the LAN; the key argument is a placeholder the
# harness requires. Direct to the box, not through llm.lwa.dk — the eval must
# measure the model, not a proxy hop.
exec "$(dirname "$0")/../../run-chunk-validated.sh" \
  "$1" "$2" \
  "http://192.168.2.173:30000/v1/chat/completions" \
  "none" \
  "glm5.3-flash"
