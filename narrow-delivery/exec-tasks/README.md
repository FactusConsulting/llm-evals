# Realistic narrow-delivery: blind + self-verify + agentic exec

Addresses two weaknesses of the chat-completion stories.yaml corpus:
1. **Answer-leak** — those prompts spell out the constraint (the fix). These BLIND
   tasks state only the goal ("fix the concurrency bug", "make Flux deploy this file"),
   never the answer.
2. **No self-verification** — there the grader ran the check. Here the model must run
   the build/test ITSELF (kustomize build / go test -race / pytest) and confirm it
   passes before finishing — the exact step it skipped in the broken production PRs.

Run via the agentic harness (real shell on the exec-host):
  cd ../../agentic && ln -sf ../narrow-delivery/exec-tasks/NDE*.yaml tasks/ && \
  python3 harness.py --model-url <url> --model-name <m> --api-key <k> \
    --exec-host ubuntu@192.168.2.175 --task NDE2-kfix

Each task: setup stages a buggy fixture under /tmp/nd/<id>; verify (ground truth) is an
independent functional check. NDE2-kfix is the literal flux-home #543 monitoring-down bug
(a kustomization referencing a file in the wrong dir).

Result — fleet Qwen3.6-35B (2026-06-22): 4/4 delivered, blind, and the model
self-verified in every task (ran the build/test, saw errors, fixed, re-ran). Capability
is there; the production failures were missing structure (atomic scope + enforced verify),
not incapacity.

NDE1-wire, NDE2-kfix, NDE3-gorace, NDE4-pyedge. (PDB/promql/dind judgment-footguns stay in
the chat corpus — no command proves their correctness.)

## Cross-domain result (2026-06-22)

Fleet Qwen3.6-35B delivered **13/13** — blind, self-verifying, ground-truth-verified —
across infra (nginx/bash/systemd), gitops (wire/kfix/promql/helm/kubeconform), and
programming (go-race/go-logic/python-edge/python-crash/sql). Does NOT prove the model
handles all tasks; it proves that tasks meeting TASK-DESIGN.md (atomic + command-checkable
+ enforced self-verify + self-contained) get delivered reliably — and that those criteria
produce dev-ready tasks. The 0/6 broad-PR failures were structure, not capability.
