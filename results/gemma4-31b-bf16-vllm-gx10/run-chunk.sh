#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/../../run-chunk-validated.sh" "$1" "$2" "http://192.168.2.173:8000/v1/chat/completions" "dummy" "gemma4-31b"
