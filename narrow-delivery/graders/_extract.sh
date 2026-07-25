#!/usr/bin/env bash
# _extract.sh <model-output-file> — prints the largest fenced code block, or the
# whole file if there are no fences. Strips ``` fences and optional lang tag.
# It must emit exactly ONE block: models often precede the real answer with a short
# "here is the broken code" example, and concatenating every block fed the graders
# unparseable YAML/source, failing otherwise-correct answers.
f="$1"
if grep -q '```' "$f"; then
  awk '
    /^[ \t]*```/ {
      if (inb) { if (length(buf) > length(best)) best = buf; buf = ""; inb = 0 }
      else     { inb = 1 }
      next
    }
    inb { buf = buf $0 "\n" }
    END {
      # an unterminated final fence still counts as a candidate block
      if (inb && length(buf) > length(best)) best = buf
      printf "%s", best
    }' "$f"
else
  cat "$f"
fi
