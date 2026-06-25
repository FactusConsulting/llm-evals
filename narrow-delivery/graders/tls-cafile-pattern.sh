#!/usr/bin/env bash
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
ob=0; ver=0
echo "$out" | grep -qE 'caFileSecret' && echo "$out" | grep -qE 'name:\s*minio-ca-bundle' && ob=1
echo "$out" | grep -qE 'key:\s*ca-bundle\.pem' && [ "$ob" = 1 ] && ver=1
# trap = SSL-verify-on but no caFileSecret → ob stays 0
echo "obedience=$ob trap_avoidance=$ob verification=$ver"
[ "$ob" = 1 ] && [ "$ver" = 1 ]
