# Narrow-delivery eval

Measures something the existing evals (knowledge, one-shot coding, open agentic) do **not**:
given a **tight, well-specified story with explicit constraints**, does the model deliver
**exactly** what was asked — correctly, wired-up, and verifiable — without wandering,
over-engineering, or ignoring stated constraints?

## Why this exists

2026-06-22: a full day of an autonomous agent's (oc-factus, Qwen3.6-35B-A3B) merged PRs were
reviewed. 0 of 6 infra PRs were ship-quality. The failures were NOT capability gaps — they
were **obedience + verification** gaps:

- added manifests but never wired them into kustomization → deployed nothing
- put a PDB footgun the story itself warned about (`minAvailable:1` on single-replica)
- scraped `/health` when the story said `/metrics`
- shipped a broken kustomization that took monitoring down for hours

The agentic benchmark score (87%) did not predict any of this. This corpus does.

## The three things each story scores

1. **obedience** — did the output satisfy every explicit constraint in the story?
2. **trap-avoidance** — did it avoid the specific known wrong answer the constraint exists to prevent?
3. **verification** — does the deliverable actually FUNCTION (the grader is a functional check:
   `kustomize build` passes, the artifact resolves, the code compiles/tests pass — never a
   diff-read or an LLM judge)?

A story only counts as **delivered** if all three pass. This is deliberately stricter than the
agentic eval: partial/plausible work scores 0, because partial/plausible is exactly the failure
mode we are trying to detect.

## Corpus

`stories.yaml` — each entry: `id`, `domain`, `prompt` (what the dev is given, verbatim),
`constraints` (the explicit must-haves), `trap` (the known wrong answer), `reference` (a known-correct
solution), `grader` (a shell command, run in the story's fixture dir, exit 0 = functionally correct).

Sources: the 7 broken oc-factus PRs (real, with known-correct fixes we just shipped) plus a couple
of genuine coding tasks (not just YAML) so the corpus exercises real code, not only manifests.

## Running

`./run.sh --model-url <url> --model-name <name> --api-key <key>` sends each story prompt to the
model, applies the prompt's output into the fixture, runs the grader, and reports per-story
obedience / trap-avoidance / verification + an aggregate delivery rate.

## The question it answers

Run it against Qwen3.6-35B (current fleet) and a candidate **more-obedient** model (e.g. a dense
model, or Gemma 26B) on the SAME narrow stories. If the higher-agentic-score model deviates more,
obedience — not raw capability or model size — is the right fleet-selection criterion. This is the
controlled comparison the campaign otherwise lacks.
