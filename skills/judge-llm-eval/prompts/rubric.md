# Scoring Rubric

## The fundamental question

For every model answer, ask **first**: *"Does this correctly solve the problem the question asked?"*

You are NOT comparing model output to reference output. You are evaluating whether the model gave a working, technically correct answer to the question. The reference is one valid solution out of many — it exists to help you verify specific factual claims, not to dictate format.

## Three ratings

| Rating | Points | Definition |
|---|---:|---|
| **pass** | 2 | The answer correctly solves what was asked. May differ in approach, wording, ordering, or specific examples from the reference. No major factual errors. |
| **partial** | 1 | The answer addresses the question but has a clear factual error, OR misses an explicitly enumerated sub-part the question demanded. |
| **fail** | 0 | The answer is wrong, doesn't address the question, contains fictitious facts (made-up resource types, non-existent flags), or refuses. |

## Default to pass

**Default rating is pass.** You should only downgrade to partial or fail when you can point to a specific concrete error in what the model wrote. If you find yourself thinking "well, the reference does it differently" → that's NOT a reason to downgrade.

Examples that are pass:

- Question: "List 3 causes for X." Reference lists causes A, B, C. Model lists causes A, D, E. **All three are valid causes** → **pass**, not partial. The question asked for 3 causes, model gave 3 valid causes.
- Question: "Show how to do X." Reference uses tool T1. Model uses tool T2 that also accomplishes X correctly. **Both work** → **pass**.
- Question: "Explain Y." Reference uses 4 sentences. Model uses 1 sentence. If the 1 sentence is correct and complete → **pass**.
- Question: "Write code that does X." Reference uses pattern P1. Model uses pattern P2 that also works. **Both achieve X** → **pass**.

Examples that are partial:

- Question: "Calculate the subnet for 10.0.0.0/20." Model says broadcast is 10.0.255.255 (wrong — should be 10.0.15.255). **Concrete factual error** → **partial**.
- Question: "Explain X, Y, and Z." Model only explains X and Y, skips Z. **Missed an enumerated sub-part** → **partial**.
- Question: "Show the exact command." Model gives the right tool but wrong flag. **Concrete syntax error** → **partial**.

Examples that are fail:

- Question: "What does command X do?" Model describes a different command. **Doesn't address the question** → **fail**.
- Question: "Write Terraform for AWS WAFv2." Model uses `field = "QUERY_STRING"` which is not valid HCL or a real WAFv2 attribute. **Fictitious syntax** → **fail**.
- Question: "Calculate Y." Model gives a wrong number with no recoverable reasoning. **Wrong answer** → **fail**.
- Code blocks containing `...` placeholders or stub comments instead of actual implementation → **fail** (not partial — the question asked for working code).

## When to use the reference answer

Use it ONLY for these checks:

1. **Numbers**: subnet math, MTU calculations, memory budgets, port numbers, header sizes
2. **Exact syntax**: command flags, function names, resource type names (e.g. `kubernetes_persistent_volume_v1` real, `kubernetes_csi_volume` fake)
3. **Domain facts**: protocol details, TLS handshake order, OAuth flow steps
4. **API surface**: stdlib function signatures, framework method names

When the model agrees with the reference on these → no fact-check needed.  
When the model disagrees with the reference on these → check independently with your own knowledge to decide who's right.

## What NOT to use the reference for

- ❌ Comparing wording or sentence structure
- ❌ Comparing the SET of items in a "list X" question (any valid X is accepted)
- ❌ Comparing the chosen approach when multiple approaches solve the problem
- ❌ Comparing length / verbosity
- ❌ Comparing which examples the model picked

## Strict on (when these are wrong → partial or fail)

- Math: subnet calculations, IP addressing, MTU overhead, memory budgets
- Syntax: exact flag names, exact field paths in HCL/YAML, exact method signatures
- Domain accuracy: SNAT vs DNAT, OAuth flows, k8s lifecycle ordering
- Command behavior: "this returns X" must be correct
- Code that doesn't compile or uses fictitious functions / resources

## Lenient on (these are NEVER reasons to downgrade)

- Wording / phrasing
- Markdown structure (list vs paragraph, headers, etc.)
- Length (concise correct beats verbose correct)
- Stylistic choices in code (var names, comment style)
- Which valid alternative the model picked from many possibilities
- Order of equivalent steps
- Whether the model's example matches the reference's example

## Chunk 9 special handling

Chunk 9 is 10 scenarios × 3 parts (A/B/C):

- **Part A** — analysis/troubleshooting. Score on whether the diagnosis is technically correct. Multiple valid diagnoses for the same problem are all pass.
- **Part B** — code/IaC writing. Code MUST be syntactically valid AND correctly solve the asked problem.
  - Code with `...` placeholders → **fail** (the question asked for working code)
  - Code that uses fictitious resources/functions → **fail**
  - Code that compiles AND solves the problem → **pass** (regardless of whether it matches reference style)
  - Code that compiles but solves the problem incompletely (e.g. missing one resource) → **partial**
- **Part C** — architecture/design. Score on whether the recommendation actually addresses the constraints stated in the prompt. Multiple valid architectures are all pass.

## The bias to fight

LLM judges (you) have a known bias: when given a reference answer, you compare item-by-item against it and call anything different "weaker" or "incomplete". **Resist this.** The reference is a hint, not a contract. The question dictates what's required, not the reference.

If you catch yourself writing "the model's answer is technically correct but the reference covers more / different / better" → that's a **pass**, not a partial.

## Set `alternative_acceptable: true` when

The model's answer is a valid alternative to what the reference shows. This includes:
- Different approach to the same problem
- Different valid items in a "list X" question
- Different example demonstrating the same concept
- Different but equivalent code pattern

This flag is for AUDITING the reference (so we can tell when our reference is too narrow over time). It does NOT change the rating — `alternative_acceptable` answers are still **pass** if they're correct.

**You should be using this flag often. Expect 10-30% of questions to have it. If you're using it less than 5%, you're probably being too strict.**
