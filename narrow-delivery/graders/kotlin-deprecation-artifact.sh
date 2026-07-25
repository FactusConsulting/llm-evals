#!/usr/bin/env bash
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
trap_hit=0; ob=0; ver=0
# trap: kotlin("android") -> kotlin-android (does not exist), OR explicit :kotlin-android:
echo "$out" | grep -qE 'kotlin\(\s*"android"\s*\)|:kotlin-android:' && trap_hit=1
# good: a REAL kotlin GRADLE-PLUGIN artifact, via the kotlin() accessor OR explicit coordinates.
# stdlib/reflect/compiler-embeddable were accepted here before — they resolve, but none of them
# supplies the Gradle plugin API needed to configure kotlinOptions, so they left the story's
# actual requirement unmet while scoring a full pass.
echo "$out" | grep -qE 'kotlin\(\s*"(gradle-plugin|gradle-plugin-api)"\s*\)' && ob=1
echo "$out" | grep -qE 'org\.jetbrains\.kotlin:kotlin-gradle-plugin(-api)?' && ob=1
[ "$ob" = 1 ] && [ "$trap_hit" = 0 ] && ver=1
echo "obedience=$ob trap_avoidance=$((1-trap_hit)) verification=$ver"
[ "$ob" = 1 ] && [ "$trap_hit" = 0 ] && [ "$ver" = 1 ]
