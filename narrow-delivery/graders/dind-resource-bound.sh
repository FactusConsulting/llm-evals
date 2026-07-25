#!/usr/bin/env bash
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
ob=0; trap_hit=0; ver=0
# memory LIMIT: look at the limits: block specifically (not requests)
limmem=$(echo "$out" | awk '/limits:/{f=1} /requests:/{f=0} f' | grep -oE 'memory:\s*"?[0-9]+Gi' | grep -oE '[0-9]+' | sort -n | tail -1)
[ -n "$limmem" ] && [ "$limmem" -ge 4 ] && ob=1
# trap = memory LIMIT of 2Gi (a 2Gi request is fine)
limlow=$(echo "$out" | awk '/limits:/{f=1} /requests:/{f=0} f' | grep -oE 'memory:\s*"?2Gi')
[ -n "$limlow" ] && trap_hit=1
# ephemeral-storage must be a LIMIT too — matching it anywhere accepted an answer that
# only set an ephemeral-storage *request*, which the story explicitly does not ask for.
limeph=$(echo "$out" | awk '/limits:/{f=1} /requests:/{f=0} f' | grep -cE 'ephemeral-storage')
[ "$limeph" -gt 0 ] && [ "$ob" = 1 ] && ver=1
echo "obedience=$ob trap_avoidance=$((1-trap_hit)) verification=$ver"
[ "$ob" = 1 ] && [ "$trap_hit" = 0 ] && [ "$ver" = 1 ]
