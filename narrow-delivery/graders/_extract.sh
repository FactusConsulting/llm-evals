#!/usr/bin/env bash
# _extract.sh <model-output-file> — prints the largest fenced code block, or the
# whole file if there are no fences. Strips ``` fences and optional lang tag.
f="$1"
if grep -q '```' "$f"; then
  awk '/^```/{if(inb){print buf; buf="";inb=0;next} else {inb=1;next}} inb{buf=buf $0 "\n"} END{if(inb)printf "%s",buf}' "$f" \
    | awk 'NF{found=1} {print} END{}' 
else
  cat "$f"
fi
