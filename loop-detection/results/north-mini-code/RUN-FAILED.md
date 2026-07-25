# This loop-detection run FAILED — do not read a loop rate out of it

All 24 generations in this directory are **zero-byte**: the run produced no model output
at all (`word_count: 0` in every score file). The two `LD12-infinite-research` scores that
say `is_spiral: true` are artifacts, not observations — LD12 is scored by looking for a
terminal phrase, and an empty file trivially lacks it. The other 22 empty responses were
scored as non-spirals for the same vacuous reason.

So this run measures nothing in either direction: it cannot show looping and it cannot
show loop-resistance. Any "2/24 spirals" figure derived from it has been withdrawn from
`DASHBOARD.md` and the model's `VERDICT.md`.

Re-running requires re-downloading the model — both GLM-4.7-Flash and North-Mini-Code
were purged from the GX10 after the campaign closed.
