#!/usr/bin/env bash
# Loop-detection eval against GLM-5.3-Flash UD-Q2_K_XL on gx10 (:30000, no-auth).
set -uo pipefail
cd "$(dirname "$0")" || exit 1
./run-eval.sh \
  --model-url http://192.168.2.173:30000 \
  --model-name glm5.3-flash-q2kxl-mtp-2x128k-gx10-run1 \
  --api-key dummy \
  --delay-between 5 \
  --verbose || echo "LOOP pass returned nonzero"
echo "LOOP-ALL-DONE"
