#!/usr/bin/env bash
# $1 = model output (the corrected counter.go). Deliver = go test -race passes AND API unchanged.
d="$(dirname "$0")/../fixtures/go-race"
tmp=$(mktemp -d); cp "$d"/go.mod "$d"/counter_test.go "$tmp"/
bash "$(dirname "$0")/_extract.sh" "$1" > "$tmp/counter.go"
ob=1; trap_hit=0
# API unchanged: signatures must remain
grep -qE 'func \(c \*Counter\) Inc\(\)' "$tmp/counter.go" || ob=0
grep -qE 'func \(c \*Counter\) Value\(\) int' "$tmp/counter.go" || ob=0
grep -qE 'type Counter struct' "$tmp/counter.go" || ob=0
[ "$ob" = 0 ] && trap_hit=1
ver=0
( cd "$tmp" && go test -race ./... >/dev/null 2>&1 ) && ver=1
echo "obedience=$ob trap_avoidance=$((1-trap_hit)) verification=$ver"
rm -rf "$tmp"
[ "$ob" = 1 ] && [ "$ver" = 1 ]
