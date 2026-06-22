#!/usr/bin/env bash
# $1 = model output. Deliver = PDB enabled AND does not deadlock single-replica drain.
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
ob=0; trap_hit=0
echo "$out" | grep -qE 'enabled:\s*true' && ob=1
# trap: minAvailable:1 (or minAvailable: "1"/100%) on a single replica
echo "$out" | grep -qE 'minAvailable:\s*"?1"?' && trap_hit=1
echo "$out" | grep -qE 'minAvailable:\s*100%' && trap_hit=1
# correct: maxUnavailable present (>=1 / a %), which permits drain
ver=0; echo "$out" | grep -qE 'maxUnavailable:\s*"?[1-9]' && ver=1
echo "$out" | grep -qE 'maxUnavailable:\s*100%' && ver=1
echo "obedience=$ob trap_avoidance=$((1-trap_hit)) verification=$ver"
[ "$ob" = 1 ] && [ "$trap_hit" = 0 ] && [ "$ver" = 1 ]
