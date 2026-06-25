#!/usr/bin/env bash
# $1 = model output (the kustomization edit / full file). Deliver = a kustomize build
# of a fixture that uses the model's resources list emits the PodMonitor.
out=$(bash "$(dirname "$0")/_extract.sh" "$1")
ob=0; ver=0
echo "$out" | grep -qE '^\s*-\s*flux-podmonitor\.yaml' && ob=1
tmp=$(mktemp -d)
cat > "$tmp/flux-podmonitor.yaml" <<'YAML'
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata: { name: flux-controllers, namespace: observability }
spec: { selector: { matchLabels: { app: flux } }, podMetricsEndpoints: [{ port: http-prom }] }
YAML
# build a kustomization from the model output (or synthesize minimal if it only gave the line)
if echo "$out" | grep -qE 'kind:\s*Kustomization'; then echo "$out" > "$tmp/kustomization.yaml"
else printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n  - flux-podmonitor.yaml\n' > "$tmp/kustomization.yaml"; fi
kustomize build "$tmp" 2>/dev/null | grep -q 'kind: PodMonitor' && ver=1
echo "obedience=$ob trap_avoidance=$ob verification=$ver"
rm -rf "$tmp"
[ "$ob" = 1 ] && [ "$ver" = 1 ]
