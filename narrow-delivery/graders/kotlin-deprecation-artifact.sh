#!/usr/bin/env bash
# Deliver = the kotlin(...) accessor maps to a REAL artifact. Static check against
# the known-nonexistent trap + known-good artifacts (no network needed).
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
trap_hit=0; ob=0; ver=0
# trap: kotlin("android") -> kotlin-android (does not exist)
echo "$out" | grep -qE 'kotlin\(\s*"android"\s*\)' && trap_hit=1
# good: kotlin("gradle-plugin") / "stdlib" / "reflect" etc are real
echo "$out" | grep -qE 'kotlin\(\s*"(gradle-plugin|stdlib|reflect|compiler-embeddable)"\s*\)' && ob=1 && ver=1
echo "obedience=$ob trap_avoidance=$((1-trap_hit)) verification=$ver"
[ "$ob" = 1 ] && [ "$trap_hit" = 0 ] && [ "$ver" = 1 ]
