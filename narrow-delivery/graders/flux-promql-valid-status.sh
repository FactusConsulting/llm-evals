#!/usr/bin/env bash
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
ob=0; trap_hit=0
echo "$out" | grep -qE 'status\s*=\s*"False"' && ob=1
echo "$out" | grep -qiE 'status\s*=\s*"Deleted"' && trap_hit=1
# verification: promtool if available, else structural (has gotk_reconcile_condition + valid)
ver=0
if command -v promtool >/dev/null; then
  printf 'groups:\n- name: t\n  rules:\n  - alert: T\n    expr: %s\n' "$(echo "$out" | tr -d '\n')" > /tmp/pr.yml
  promtool check rules /tmp/pr.yml >/dev/null 2>&1 && ver=1
else
  echo "$out" | grep -qE 'gotk_reconcile_condition' && [ "$trap_hit" = 0 ] && ver=1
fi
echo "obedience=$ob trap_avoidance=$((1-trap_hit)) verification=$ver"
[ "$ob" = 1 ] && [ "$trap_hit" = 0 ] && [ "$ver" = 1 ]
