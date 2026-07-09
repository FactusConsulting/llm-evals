#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-capture.sh" "$1" "$2" "http://192.168.2.173:8000/v1/chat/completions" "dummy" "north-mini-code"
