#!/usr/bin/env bash
# Loop-detection passes 2 and 3 against GLM-5.3-Flash UD-Q2_K_XL on gx10 (:30000, no-auth).
# Each pass lands in its own results dir so the three passes stay separable.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
for i in 2 3; do
  echo "================ LOOP-DETECTION PASS ${i}/3 $(date +%H:%M:%S) ================"
  ./run-eval.sh \
    --model-url http://192.168.2.173:30000 \
    --model-name "glm5.3-flash-q2kxl-mtp-2x128k-gx10-run${i}" \
    --api-key dummy \
    --delay-between 5 \
    --verbose || echo "LOOP pass ${i} returned nonzero"
done
echo "LOOP-ALL-DONE"
