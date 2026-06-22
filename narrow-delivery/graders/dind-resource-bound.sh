#!/usr/bin/env bash
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
ob=0; trap_hit=0; ver=0
# parse memory limit value (Gi)
mem=$(echo "$out" | grep -oE 'memory:\s*"?[0-9]+Gi' | grep -oE '[0-9]+' | sort -n | tail -1)
[ -n "$mem" ] && [ "$mem" -ge 4 ] && ob=1
echo "$out" | grep -qE 'memory:\s*"?2Gi' && trap_hit=1
echo "$out" | grep -qE 'ephemeral-storage' && [ "$ob" = 1 ] && ver=1
echo "obedience=$ob trap_avoidance=$((1-trap_hit)) verification=$ver"
[ "$ob" = 1 ] && [ "$trap_hit" = 0 ] && [ "$ver" = 1 ]
