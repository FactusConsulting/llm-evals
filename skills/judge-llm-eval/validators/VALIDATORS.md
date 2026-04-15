# Part B Code Validators

`validate-part-b.py` extracts fenced code blocks from chunk 9 Part B answers
and runs each through the appropriate syntax validator. The result is a
**hard signal** that judges should treat as authoritative for code quality.

## Why deterministic validation

Chunk 9 Part B is the highest-variance area in the eval. Models produce code
that *looks* right to a human reader but is subtly broken:

- AWS WAFv2 with invented statement names (`rate_limit` instead of `rate_based_statement`)
- Terraform resources that don't exist (`kubernetes_csi_volume`)
- `kubectl get … -o jsonpath` selectors that crash on null fields
- Bash with broken parameter expansion
- HCL where `field = "X"` should be `field { x { } }`

A judge reading this often calls it "partial — looks reasonable but X is wrong",
and the call swings depending on which judge sees it. A validator either says
✓ or ✗ — no opinion.

## Usage

```bash
python3 skills/judge-llm-eval/validators/validate-part-b.py \
  results/<model>/run<N>/chunk9-response.txt
```

Outputs JSON to stdout. Pipe to `jq` for inspection.

## Validators by language

| Code-fence tag | Validator command | What it checks |
|---|---|---|
| `bash`, `sh` | `shellcheck -s bash -S error -` | Syntax + critical errors only (warnings ignored) |
| `python`, `py` | `python3 -m py_compile` | Compiles to bytecode |
| `jq` | `jq -n <expression>` | jq grammar |
| `yaml` | `python3 -c 'yaml.safe_load_all'` + `kubectl apply --dry-run=client` (if k8s manifest) | YAML syntax + k8s schema |
| `hcl`, `terraform`, `tf` | `terraform fmt -check` (looks for `Error:` in stderr) | HCL grammar |
| `json` | `json.loads` | JSON grammar |
| `sql`, `go`, `rust` | (unvalidated) | reported as `ok=null` |

## How judges should use it

A judge prompt template can include the validator output for the corresponding
Part B answer. The judge is told:

> "The following Part B code blocks were validated automatically. **Code that
> the validator flagged as invalid (`ok: false`) cannot rate higher than
> partial.** If the model uses a fictitious resource type or syntax that fails
> validation, rate it fail unless the rest of the answer compensates."

## What it doesn't do (and why that's OK)

1. **No provider semantics**: `terraform fmt -check` validates HCL grammar only,
   not provider attribute names. A `kubernetes_csi_volume` block parses fine
   even though the resource doesn't exist. **Mitigation**: judges still verify
   resource type names against the reference answer.

2. **No runtime testing**: bash that's syntactically valid might still do the
   wrong thing. Python that compiles might raise at runtime. **Mitigation**:
   judges still read the code for logical correctness.

3. **No SQL/Go/Rust validation yet**: SQL needs a database or stub parser, Go
   needs a temp module, Rust needs a stub crate. **Mitigation**: judges fall
   back to manual review for these. Could be added later.

4. **No HCL semantic validation**: Need `terraform validate` which requires
   `terraform init` which needs providers downloaded. Heavy but possible —
   could be a separate `validate-part-b-deep.sh` that builds a stub backend
   and pre-downloads common providers (aws, kubernetes, helm, null).

## Test results on existing v2 runs

Validated runs 1-3 of `gemma4-26b-q6k-458k-turbo4-v2-ai-infer2/chunk9-response.txt`:

| Scenario | Run 1 | Run 2 | Run 3 | Pattern |
|---|---|---|---|---|
| SC1 (jq) | ✓ | ✓ | ✓ | always valid |
| SC2 | (no code) | (no code) | (no code) | model writes prose only |
| SC3 (bash) | ✓ | ✓ | ✓ | always valid |
| SC4 (HCL) | ✗ | ✓ | ✗ | **flaky** — k8s csi syntax |
| SC5 (sql/go) | unvalidated | unvalidated | unvalidated | needs new validator |
| SC6 (HCL) | ✗ | ✗ | ✗ | **persistently broken** — Transit Gateway HCL |
| SC7 (yaml) | ✓ | ✓ | ✓ | always valid |
| SC8 (bash) | ✓ | ✓ | ✓ | always valid |
| SC9 (HCL) | ✗ | ✗ | ✗ | **persistently broken** — WAFv2 invalid statement names |
| SC10 (yaml) | ✓ | ✓ | ✓ | always valid |

**Insight**: SC6 (Transit Gateway) and SC9 (WAFv2) are persistent failure modes
for Gemma 4 26B Q6_K. No amount of re-prompting fixes them. This is a real
model limitation that the validator surfaces deterministically.

## Future improvements

1. **Stub Terraform backend + providers** for `terraform validate` (semantic check)
2. **SQL validator** via `sqlglot` (Python parser, no DB needed)
3. **Go validator** via temp `go.mod` + `go vet ./...`
4. **Auto-feed validator results to judges** — currently the orchestrator passes them; could be inlined
5. **Cross-language detection improvement** — currently relies on fenced code-block language tag; some models forget to tag, falls back to "unknown"
