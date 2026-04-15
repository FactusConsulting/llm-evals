# Cross-Domain Scenarios — Answers

---

## SC1 — Broken Deployments After Cluster Upgrade

### Part A — Analysis
**Answer:**
Kubernetes Pod Security Standards (PSS) are enforced by the built-in PodSecurity admission controller on a per-namespace basis via the `pod-security.kubernetes.io/enforce=<level>` label. The three levels are Privileged, Baseline, and Restricted.

Under **Baseline**, the primary constraint related to root is that `hostNetwork`, `hostPID`, privilege escalation via `allowPrivilegeEscalation` and certain capabilities are restricted, but running as UID 0 is still permitted. Under **Restricted**, the rules tighten considerably: the pod/container `securityContext` MUST set `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, drop ALL capabilities (and add back only `NET_BIND_SERVICE` if needed), and set `seccompProfile.type` to `RuntimeDefault` or `Localhost`.

The key interaction is between the `runAsNonRoot` flag and the container image's `USER` directive. When `runAsNonRoot: true` is set but no explicit `runAsUser` is provided, the kubelet refuses to start the container if it cannot positively verify at admission/runtime that the image's effective UID is non-zero. The kubelet reads the OCI image config and inspects the `Config.User` field:

- If the field is empty or `"root"` or `"0"`, the container will be blocked with a `CreateContainerConfigError` or fail liveness with `container has runAsNonRoot and image will run as root`.
- If the field is a numeric UID != 0, it passes.
- If it is a username like `nobody`, the kubelet cannot resolve the UID before start and fails the check.

The Chainguard `static:latest` image recently changed its default `USER` from `65532` (nonroot) to effectively `root` (or the tag was rebuilt with a different default), so the rebuilt images no longer carry an image-level nonroot UID. Under Baseline, this was tolerated. Under Restricted with `runAsNonRoot: true` and no explicit `runAsUser`, the admission/runtime check fails and the pods CrashLoop (repeatedly fail to start the container).

The 70% that are fine either already specify `runAsUser: <non-zero>` in their spec, run in namespaces still labeled Baseline, or use images whose `Config.User` still resolves to a non-zero UID.

### Part B — Code/IaC
**Answer:**
```bash
kubectl get pods --all-namespaces -o json | jq -c '.items[] | select(.status.containerStatuses[]? | .state.waiting.reason == "CrashLoopBackOff") | {namespace: .metadata.namespace, pod: .metadata.name, podSecurityContext: (.spec.securityContext // {}), containerSecurityContexts: [.spec.containers[] | {name: .name, securityContext: (.securityContext // {})}]}'
```

This emits one JSON object per CrashLoopBackOff pod with namespace, pod name, pod-level `securityContext`, and per-container `securityContext` settings.

### Part C — Architecture
**Answer:**
**Immediate fix (image level):** Pin to `cgr.dev/chainguard/static:latest-nonroot` (or the digest of a known-good nonroot variant), which sets `USER 65532`. For images you build yourself, add an explicit `USER 65532` (or another fixed non-zero UID) and `COPY --chown=65532:65532` for any writable paths.

**Manifest fix:** Set explicit UIDs at the pod level so the kubelet never has to resolve image metadata:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  runAsGroup: 65532
  fsGroup: 65532
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

**CI gate:** Run `kube-linter`, `kubeconform`, and `kyverno test` against manifests in PR, plus a dry-run admission test against a cluster labeled `pod-security.kubernetes.io/enforce=restricted`. Add a Trivy / Grype job that runs `docker inspect` and fails if `Config.User` is empty or `"0"`. Add a Conftest/OPA policy in CI that requires `runAsUser` and `runAsNonRoot` to be set explicitly.

**Rollout without downtime:** Because pods are already CrashLooping, we have a partial outage. The fastest safe path is:
1. Temporarily re-label affected namespaces to `pod-security.kubernetes.io/enforce=baseline` (keep `warn=restricted` and `audit=restricted`) to restore service.
2. Patch each Deployment to add an explicit `runAsUser` via `kubectl patch` or a GitOps commit; rolling update handles the restart.
3. Once all workloads are patched and green, re-enable `enforce=restricted`.
4. Add CI gate and Kyverno cluster policy `require-run-as-non-root` to block any future regression.

---

## SC2 — Cross-Region Database Failover Gone Wrong

### Part A — Analysis
**Answer:**
RDS cross-region read replicas use PostgreSQL **asynchronous streaming replication** over an AWS-managed encrypted link. WAL records are generated on the primary, flushed to local storage, shipped to the replica, applied, and only then visible to replica readers. With asynchronous replication there is no primary-side wait for the replica's acknowledgement, so any transaction committed on the primary but not yet shipped/applied on the replica is lost when the primary becomes unreachable.

The replication lag implication is that **whatever was in `pg_stat_replication.write_lag + flush_lag + replay_lag` at the moment of the outage is your data-loss window**. Across regions (us-east-1 → eu-west-1) that is typically a few hundred milliseconds to several seconds under load, and can balloon to minutes if the primary was under heavy write pressure or the inter-region link was degraded — which is exactly the scenario during an outage. Data loss includes all transactions whose commit records had not been streamed and applied before promotion.

The "stale data" symptom after promotion is a different problem: applications talking to **multiple** endpoints (some still cached on old connection info, some using read replicas of the new primary, or stale PgBouncer pool entries) see inconsistent views. Some queries may also be hitting PgBouncer sessions that were in the middle of a transaction at failover and got reset, producing partial reads.

To quantify the data-loss window:
- Check the promoted replica's `pg_controldata` output for the last replayed WAL LSN, compare with any surviving primary metrics (CloudWatch `OldestReplicationSlotLag`, `ReplicaLag`).
- Query `SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn();` on the replica just before promotion.
- Inspect CloudWatch `ReplicaLag` metric history for the minutes preceding the outage.
- Diff application-level audit logs (order IDs, event IDs) from the application tier against what is present in the new primary to identify specific lost records.

### Part B — Code/IaC
**Answer:**
The goal: stop Terraform from believing the old `aws_db_instance` is authoritative, import the promoted replica as a standalone `aws_db_instance`, and re-point references so `terraform plan` is a no-op.

```bash
# 1. Back up state first.
terraform state pull > state.backup.$(date -u +%Y%m%dT%H%M%SZ).json

# 2. Remove the old, unreachable primary from state (do NOT destroy it via Terraform;
#    the instance is gone/unreachable in us-east-1 and will be cleaned up separately).
terraform state rm aws_db_instance.primary

# 3. Rename / add a new resource block for the promoted replica, e.g.
#    resource "aws_db_instance" "primary" { identifier = "app-db-euw1" ... }
#    using lifecycle { ignore_changes = [replicate_source_db, password] }.

# 4. Import the promoted replica into the new address.
terraform import aws_db_instance.primary app-db-euw1

# 5. For dependent resources that hardcoded the old ARN (security groups referencing
#    db_instance.arn, Route53 records, parameter group attachments), update the HCL to
#    reference aws_db_instance.primary.arn / .endpoint / .address and then:
terraform plan -out=tfplan
# Review — it must show 0 to add, 0 to destroy, only in-place metadata updates.

# 6. For Route53 records pointing at the old endpoint, update the record set value in HCL
#    and apply; Route53 supports in-place record updates with no recreation.
terraform apply tfplan

# 7. If a resource is hopelessly tied to the old ARN and plan wants to destroy+recreate,
#    use targeted moves instead:
terraform state mv aws_db_parameter_group.old aws_db_parameter_group.primary
# or add lifecycle { ignore_changes = [<attr>] } temporarily, then reconcile on next PR.
```

Key points: `terraform state rm` removes state without touching the real resource; `terraform import` pulls the promoted replica in under its new address; `ignore_changes` on `replicate_source_db` prevents Terraform from trying to re-establish replication from the (gone) old primary.

### Part C — Architecture
**Answer:**
**Connection management:** Prefer **RDS Proxy** over self-managed PgBouncer for this workload. RDS Proxy handles failover transparently (connection pinning and re-routing), integrates with IAM auth and Secrets Manager for automatic credential rotation, and survives primary promotion without the "server login retry" storm PgBouncer is exhibiting (PgBouncer caches backend DSNs and needs explicit reconfiguration). PgBouncer is still useful as a transaction-mode pooler close to the application for prepared-statement efficiency, but should sit **behind** RDS Proxy or be replaced by it.

**DNS failover:** Put a Route53 record in front of the database endpoint with health checks on a lightweight TCP/SQL probe; use `failover` routing policy with primary/secondary records. Applications connect to the CNAME, not the raw RDS endpoint. TTL should be low (10–30s). This decouples applications from Terraform-managed endpoint strings.

**Application-level retry:** Use exponential backoff with jitter, a circuit breaker on the connection pool (e.g., HikariCP's `initializationFailTimeout` and `connectionTestQuery`), and idempotency keys on all write endpoints so retries after failover do not duplicate transactions. Expose `readiness` probes that check DB connectivity so K8s removes unhealthy pods from service.

**RPO < 1s:** Standard cross-region RDS read replicas are asynchronous and cannot guarantee sub-second RPO under load. **Aurora Global Database** is the correct choice: it replicates at the storage layer with typical cross-region lag under 1s (often <100ms), supports managed planned failover, and provides a Global endpoint. Promotion time is roughly 60s. For this workload I would recommend migrating from RDS PostgreSQL to **Aurora PostgreSQL Global Database** with:
- Primary cluster in us-east-1, secondary in eu-west-1 (and optionally a third region).
- RDS Proxy endpoints in each region.
- Route53 geo + failover routing in front of the proxies.
- Patroni-style application awareness is not needed — Aurora handles it.

Trade-offs of Aurora Global: higher cost, vendor lock-in, some parameter-group differences from community PostgreSQL. But for a regulated cross-region HA requirement with RPO < 1s and the operational simplicity your team needs, it is the right answer.

---

## SC3 — Container Image Supply Chain Compromise

### Part A — Analysis
**Answer:**
**Containment without destroying evidence:**

1. **Isolate, do not delete.** Add a `NetworkPolicy` that denies all egress/ingress from the affected pods (match on a label), or apply a Calico `GlobalNetworkPolicy` with `action: Deny`. Alternatively cordon the nodes and taint them `quarantine=true:NoSchedule`, then use `kubectl label pod <name> quarantine=true` so a controller evicts only non-quarantined pods. Do **not** `kubectl delete pod` — that destroys the container filesystem.

2. **Snapshot the running container** before killing it:
   - `kubectl debug node/<node> -it --image=ubuntu` to get a root shell on the host.
   - From the host: `crictl ps | grep <pod>`, then `crictl inspect <containerID>` for metadata, `crictl exec <containerID> ps auxf` for process tree.
   - `nsenter -t <pid> -n -p ss -tunap` for network connections inside the container netns.
   - `nsenter -t <pid> -m -p find / -newer /etc/os-release -type f 2>/dev/null` to list files modified since image build.
   - `nsenter -t <pid> -m -p cat /proc/<suspicious_pid>/maps` and `ls -la /proc/<suspicious_pid>/exe` to identify the unknown `/tmp/.x` binary.
   - Copy `/tmp/.x` off the container: `kubectl cp <ns>/<pod>:/tmp/.x ./evidence/.x`.
   - `docker commit` equivalent via `crictl` is not supported; use `ctr -n k8s.io containers export` or `tar` the container's rootfs via `/proc/<pid>/root/`.

3. **Capture memory and process state:**
   - `cat /proc/<pid>/status`, `/proc/<pid>/cmdline`, `/proc/<pid>/environ`.
   - Use `gcore <pid>` if `gdb` is available, or `criu dump` for a full checkpoint.

4. **Collect Kubernetes evidence:**
   - `kubectl logs <pod> --previous` for prior restarts.
   - `kubectl get events -n <ns> --sort-by=.lastTimestamp`.
   - Falco alert JSON payloads from the SIEM.
   - AuditLog entries for recent `exec` or `patch` events against the pod.

5. **Only then kill** the pod (`kubectl delete pod --grace-period=0`) and scale the Deployment to zero. Rotate any ServiceAccount tokens the pod could have mounted, and any cloud credentials (IRSA / IAM role) it could have assumed. Revoke ECR pull credentials that the compromised image was built against.

6. **Hunt laterally:** search logs for processes spawned by any pod running `api-gateway:v2.4.1` in the last 6 hours, DNS queries to suspicious hosts, and outbound traffic to non-whitelisted destinations.

### Part B — Code/IaC
**Answer:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Compare build-time digest of node:20-slim against upstream Docker Hub,
# then enumerate layers of api-gateway:v2.4.1 in ECR and flag unknown ones.

BUILD_DIGEST_FROM_CI="${BUILD_DIGEST_FROM_CI:?must set: digest recorded at build time}"
ECR_REGISTRY="${ECR_REGISTRY:?e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com}"
ECR_REPO="${ECR_REPO:-api-gateway}"
ECR_TAG="${ECR_TAG:-v2.4.1}"
KNOWN_GOOD_LAYERS_FILE="${KNOWN_GOOD_LAYERS_FILE:-./known-good-layers.txt}"
AWS_REGION="${AWS_REGION:-us-east-1}"

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }
command -v aws >/dev/null || { echo "aws cli required" >&2; exit 1; }

echo "== Step 1: fetch upstream node:20-slim digest from Docker Hub =="
TOKEN=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/node:pull" | jq -r .token)
UPSTREAM_MANIFEST=$(curl -fsSL \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  "https://registry-1.docker.io/v2/library/node/manifests/20-slim")
UPSTREAM_DIGEST=$(printf '%s' "${UPSTREAM_MANIFEST}" \
  | jq -r '.manifests[]? | select(.platform.architecture=="amd64" and .platform.os=="linux") | .digest' \
  | head -n1)

printf 'build-time digest : %s\n' "${BUILD_DIGEST_FROM_CI}"
printf 'upstream  digest  : %s\n' "${UPSTREAM_DIGEST}"
if [[ "${BUILD_DIGEST_FROM_CI}" != "${UPSTREAM_DIGEST}" ]]; then
  printf '>>> MISMATCH: base image digest drifted since build time\n'
else
  printf '    base image digest matches current upstream\n'
fi

echo
echo "== Step 2: fetch api-gateway:${ECR_TAG} manifest from ECR =="
MANIFEST_JSON=$(aws ecr batch-get-image \
  --region "${AWS_REGION}" \
  --repository-name "${ECR_REPO}" \
  --image-ids "imageTag=${ECR_TAG}" \
  --query 'images[0].imageManifest' \
  --output text)

LAYERS=$(printf '%s' "${MANIFEST_JSON}" | jq -r '.layers[]?.digest // .fsLayers[]?.blobSum')
echo "Layers in ${ECR_REPO}:${ECR_TAG}:"
printf '%s\n' "${LAYERS}" | nl -ba

echo
echo "== Step 3: flag layers not in known-good manifest =="
if [[ ! -f "${KNOWN_GOOD_LAYERS_FILE}" ]]; then
  printf '    WARNING: %s missing; cannot diff layers\n' "${KNOWN_GOOD_LAYERS_FILE}"
  exit 0
fi

UNKNOWN=0
while IFS= read -r layer; do
  [[ -z "${layer}" ]] && continue
  if ! grep -Fxq "${layer}" "${KNOWN_GOOD_LAYERS_FILE}"; then
    printf '>>> UNKNOWN LAYER: %s\n' "${layer}"
    UNKNOWN=$((UNKNOWN + 1))
  fi
done <<< "${LAYERS}"

if (( UNKNOWN > 0 )); then
  printf '\nFAIL: %d unknown layer(s) detected\n' "${UNKNOWN}"
  exit 2
fi
printf '\nOK: all layers match known-good set\n'
```

### Part C — Architecture
**Answer:**
**Hardened CI/CD pipeline design:**

1. **Base image pinning by digest.** Dockerfiles use `FROM node:20-slim@sha256:<digest>`, never a floating tag. Digest updates are proposed by Renovate/Dependabot, reviewed in a PR, and require a fresh Trivy/Grype scan and an SBOM diff before merge.

2. **Reproducible builds in ephemeral runners.** Builds run on ephemeral CI runners (GitHub Actions, GitLab runners, or Tekton) with no persistent state. Use `docker buildx build --provenance=true --sbom=true` (BuildKit attestations) so each image ships an in-toto provenance attestation and an SPDX/CycloneDX SBOM as OCI referrers.

3. **Signing with Cosign / Sigstore.** After build, sign the image (and the SBOM and provenance attestations) with `cosign sign --keyless` using OIDC identity from the CI runner. Fulcio issues a short-lived certificate bound to the workflow identity; signatures land in Rekor's transparency log. No long-lived keys to steal.

4. **Admission-time verification.** Deploy **Kyverno** (or Sigstore Policy Controller / Connaisseur) with a `verifyImages` policy that rejects any pod whose image is not signed by the expected Fulcio identity (e.g., `https://github.com/myorg/api-gateway/.github/workflows/release.yml@refs/heads/main`). Policy also requires an attached SBOM attestation and a provenance attestation that matches the expected builder.

5. **SBOM generation and vuln management.** `syft` produces the SBOM, `grype`/`trivy` scans it continuously against the CVE feed. New CVEs affecting a deployed image trigger a rebuild, not a re-scan of a potentially tampered artifact.

6. **Build isolation.** The build pipeline runs in an account/project separate from developers. ECR push credentials are OIDC-federated from CI only; no human has push rights. Pull-through caches sit in front of Docker Hub to avoid tag moves.

7. **Notary v2 / OCI 1.1 referrers.** Notary v2 (now "notation" project) provides an alternative signing format with OCI 1.1 referrer relationships, letting signatures, SBOMs, and attestations attach directly to the image manifest in the registry without a separate tag scheme. It is complementary to Cosign (Cosign uses its own tag-based discovery; notation uses referrers). Either is acceptable — pick one and enforce it at admission. Notary v2 is better if you need OCI-native discoverability across vendors; Cosign/Sigstore is better for keyless signing and transparency-log auditability.

8. **Runtime detection as defense-in-depth.** Falco + Tetragon continue to monitor for anomalous process trees; these rules would have caught `/tmp/.x` regardless of the signing story.

---

## SC4 — Migrating a Stateful Monolith to Kubernetes

### Part A — Analysis
**Answer:**
**Top 5 blockers and solutions:**

1. **In-memory sticky sessions.** Kubernetes pods are ephemeral; rolling updates and node failures destroy local session state. Session affinity via Ingress `sessionAffinity: ClientIP` is fragile (NAT, mobile clients) and does not survive pod restarts. **Solution:** externalize sessions to Redis (Spring Session / `javax.servlet.http.HttpSession` backed by `spring-session-data-redis`) or to JWTs, so any pod can serve any request.

2. **Local filesystem writes to `/data/uploads`.** A single pod with `RWO` storage cannot scale horizontally, and pod rescheduling on a different node loses data. **Solution:** mount the existing NFS export via `nfs.csi.k8s.io` as a `ReadWriteMany` PVC so all replicas share it, or (preferred) migrate uploads to S3/MinIO behind a thin compatibility layer and keep NFS only for the legacy read path during transition.

3. **On-prem Oracle 19c dependency.** Kubernetes ingress/egress must reach a specific on-prem network, clients need Oracle wallet / TNS configuration, and connection-pool churn during rollouts can hammer Oracle. **Solution:** expose Oracle via an internal `Service` of `type: ExternalName`, route via a VPN / Direct Connect / dedicated interconnect, pin connection pool sizing per-pod with `HikariCP`, and use a PodDisruptionBudget so rolling updates do not thrash Oracle logins. Longer term, evaluate Oracle → PostgreSQL with the Ora2Pg tool, but that is out of scope for a 6-month migration.

4. **IBM MQ integration.** MQ clients need a specific channel definition, mutual TLS, and often host-based allowlisting. Pod IPs are ephemeral. **Solution:** front pods with a dedicated `Service` of type `LoadBalancer` (or a static egress IP via egress gateway / Istio egress) so MQ sees a stable source address; use the IBM MQ Kubernetes Operator (`ibm-mq`) or a sidecar `mqclient` container that holds the CCDT and client auth; place the channel credentials in a `Secret` mounted read-only.

5. **Monolithic startup time and 2s p99 latency budget.** Java 11 monoliths often take 60–120s to warm up JIT and load classes, which breaks liveness probes and blows the p99 budget when a pod is rescheduled. **Solution:** use `startupProbe` with a generous `failureThreshold` before switching to the normal `livenessProbe`, configure JVM with `-XX:+UseG1GC -Xms=Xmx`, enable class data sharing (CDS) / AppCDS, and consider GraalVM native-image or Java 21 CRaC if upgrade is tolerable. Set `readinessProbe` only to pass after JIT warm-up traffic has run.

(Honorable mentions: hardcoded log paths → switch to stdout; process-local cron jobs → `CronJob`; file-based configuration → `ConfigMap`; secrets in properties files → `Secret`/External Secrets; F5 iRules → Envoy/Istio filters or Ingress annotations.)

### Part B — Code/IaC
**Answer:**
```hcl
# modules/nfs-storage/variables.tf
variable "nfs_server" {
  type        = string
  description = "FQDN or IP of the NFS server backing /data/uploads."
}

variable "nfs_export_path" {
  type        = string
  description = "Exported path on the NFS server (e.g. /exports/uploads)."
  default     = "/exports/uploads"
}

variable "storage_capacity" {
  type        = string
  description = "Requested storage capacity (e.g. 500Gi)."
  default     = "500Gi"
}

variable "namespace" {
  type        = string
  description = "Namespace where the PVC will be created."
}

variable "storage_class_name" {
  type        = string
  default     = "nfs-uploads"
}

variable "pv_name" {
  type        = string
  default     = "pv-uploads"
}

variable "pvc_name" {
  type        = string
  default     = "uploads"
}

# modules/nfs-storage/main.tf
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.27.0"
    }
  }
}

resource "kubernetes_storage_class_v1" "nfs_uploads" {
  metadata {
    name = var.storage_class_name
  }
  storage_provisioner = "nfs.csi.k8s.io"
  reclaim_policy      = "Retain"
  volume_binding_mode = "Immediate"
  parameters = {
    server = var.nfs_server
    share  = var.nfs_export_path
  }
  mount_options = [
    "nfsvers=4.1",
    "hard",
    "timeo=600",
    "retrans=2",
    "noresvport",
  ]
}

resource "kubernetes_persistent_volume_v1" "uploads" {
  metadata {
    name = var.pv_name
  }
  spec {
    capacity = {
      storage = var.storage_capacity
    }
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class_v1.nfs_uploads.metadata[0].name
    persistent_volume_reclaim_policy = "Retain"
    mount_options = [
      "nfsvers=4.1",
      "hard",
      "noresvport",
    ]
    persistent_volume_source {
      csi {
        driver        = "nfs.csi.k8s.io"
        volume_handle = "${var.nfs_server}#${var.nfs_export_path}#"
        volume_attributes = {
          server = var.nfs_server
          share  = var.nfs_export_path
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "uploads" {
  metadata {
    name      = var.pvc_name
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class_v1.nfs_uploads.metadata[0].name
    volume_name        = kubernetes_persistent_volume_v1.uploads.metadata[0].name
    resources {
      requests = {
        storage = var.storage_capacity
      }
    }
  }
}

# modules/nfs-storage/outputs.tf
output "pvc_name" {
  value = kubernetes_persistent_volume_claim_v1.uploads.metadata[0].name
}
output "storage_class_name" {
  value = kubernetes_storage_class_v1.nfs_uploads.metadata[0].name
}
```

**Why ReadWriteMany:** The legacy monolith is deployed as multiple replicas (F5 load-balances across 8 servers) that all write and read the same `/data/uploads` directory. In Kubernetes, that translates to multiple pods mounting the same `PersistentVolume`. `ReadWriteOnce` allows only a single node to mount the volume at a time, so scaling replicas across nodes fails; `ReadWriteOncePod` is even stricter (one pod). Only `ReadWriteMany` lets all pods on all nodes mount simultaneously, which is exactly what an NFS export provides natively. If we moved uploads to S3 later, we'd drop the PVC entirely and talk to the object store directly.

### Part C — Architecture
**Answer:**
**Strangler Fig phased migration:**

**Phase 0 — Parallel infrastructure (weeks 1–4).**
- Stand up the Kubernetes cluster, CI/CD, observability, NFS CSI module, External Secrets, and a network path to Oracle and IBM MQ.
- Build the monolith container image with `startupProbe`, externalized logging, and externalized config.
- Run the containerized monolith in a "shadow" Kubernetes deployment receiving **mirrored** read-only traffic from F5 (Istio mirror or Envoy tap). No user traffic lands on it. Success metric: error rate < 0.1%, p99 latency within 20% of bare-metal over a 7-day window.

**Phase 1 — 10% cutover to Kubernetes for stateless read endpoints (weeks 5–10).**
- Place an Istio Ingress (or NGINX Ingress) in front of the K8s Deployment.
- On F5, add a pool member pointing at the K8s Ingress. Use F5 "ratio" load balancing to send 10% of traffic to K8s for endpoints already proven safe by shadow.
- Externalize sessions to Redis for these endpoints so affinity between requests is not required.
- Go/no-go metrics: 5xx error rate, p99 latency (<2.2s), Oracle session count stable, F5 pool health. Rollback: set ratio back to 0%.

**Phase 2 — 100% of reads + writes (excluding IBM MQ) via K8s (weeks 11–18).**
- Bump F5 ratio to 100% for K8s; keep bare-metal pool as hot standby.
- Move `/data/uploads` writes: new writes go to K8s pods via the shared NFS PVC; bare-metal and K8s share the same NFS export during this window, so reads are consistent.
- Switch DNS `app.example.com` to point at the K8s Ingress directly, retiring the F5 VIP for this app (or keep F5 as a lower-tier LB with pool members = K8s Ingress only).
- Rollback: revert DNS TTL 60s, re-enable F5 → bare-metal pool.

**Phase 3 — IBM MQ integration on K8s (weeks 19–24).**
- Deploy MQ client sidecar / egress gateway with a pinned source IP (via Cilium egress gateway or dedicated NAT).
- Cut MQ channel from bare-metal IPs to the new egress IP.
- Validate queue depth, consumer lag, and dead-letter queue counts for 72 hours.
- Decommission bare-metal fleet, keeping two nodes on standby for 30 days.

**Traffic split:** During phases 1–2 the F5 remains the top-level LB, using pool ratios for canary control. An Istio VirtualService inside K8s provides a second level of weighted routing for finer per-endpoint control.

**IBM MQ handling:** Because MQ uses persistent TCP channels bound to source IPs, the K8s side needs a stable egress IP. Use a Cilium egress gateway (or AWS NAT Gateway / F5 SNAT pool) so all pod traffic egresses from a known address that matches the MQ channel's IP allowlist.

**Rollback per phase:** Each phase has a single dial: F5 pool ratio, DNS weight, or MQ channel target. Rollback is flipping the dial back and waiting for TTL expiration.

**Go/no-go metrics per phase:** p99 < 2.2s, error rate < 0.2%, Oracle active sessions within baseline ±10%, MQ queue depth stable, no increase in customer support tickets over a 48-hour window.

---

## SC5 — Mysterious Latency Spike in Microservices

### Part A — Analysis
**Answer:**
**Systematic debugging approach:**

1. **Start with the distributed trace.** Open Jaeger/Tempo and filter `checkout-service` traces with `duration > 2s` in the 14:00–14:30 window. A single trace pinpoints which span is slow. The mesh metrics already say "between checkout-service and inventory-service," so the candidate spans are:
   - `checkout-service` egress sidecar (outbound Envoy).
   - Network hop.
   - `inventory-service` ingress sidecar (inbound Envoy).
   - `inventory-service` application.
   - `inventory-service` → downstream DB span.
   
2. **Envoy metrics (via `istio_requests_total` and `envoy_cluster_*`):**
   - `envoy_cluster_upstream_rq_time_bucket{cluster="outbound|80||inventory-service..."}` — end-to-end upstream latency from checkout-service's sidecar. If this matches the observed spike, latency is upstream (network or inventory-service).
   - `envoy_cluster_upstream_cx_active` and `envoy_cluster_upstream_cx_connect_ms_bucket` — if connect time spikes, it's TCP/TLS handshake problem.
   - `envoy_cluster_upstream_rq_pending_overflow` and `envoy_cluster_upstream_rq_pending_active` — non-zero means Envoy is queueing requests because `max_pending_requests` or `max_requests` is saturated (proxy-level queueing).
   - `envoy_cluster_upstream_rq_retry` and `..._rq_timeout` — retries indicate transient upstream failures.
   - `istio_request_duration_milliseconds` grouped by `source_workload`, `destination_workload`, and `response_code`.
   
3. **Distinguish proxy queueing vs. upstream latency.**
   - If `envoy_cluster_upstream_rq_pending_active` spikes → circuit-breaker limit too low, requests are queued in the sidecar.
   - If `upstream_cx_active` is at its max → connection pool exhaustion.
   - If only `upstream_rq_time` spikes but pending/active do not → upstream (network or inventory-service) is slow.
   
4. **Kubernetes + node metrics:**
   - `kubelet_running_pods`, `container_network_transmit_packets_dropped_total`, `node_netstat_TcpExt_TCPRetransSegs` on both nodes to rule out packet loss.
   - `container_cpu_cfs_throttled_seconds_total` — CPU throttling can cause slowdown even when CPU utilization looks low.
   
5. **Inventory-service application metrics:**
   - DB connection pool (HikariCP / `pg_stat_activity`) — wait time, active connections, pool exhaustion.
   - GC pauses (if JVM) / stop-the-world events.
   - Request handler queue length and goroutine count (Go's `go_goroutines`).
   
6. **Check for batch jobs and CronJobs.** `kubectl get cronjobs -A` and Grafana dashboards on scheduled workloads. A cron at 14:00 UTC is the smoking gun.

7. **Database-side:** query `pg_stat_statements`, `pg_locks`, and `pg_stat_activity` for the 14:00 window to spot long-running queries, lock waits, and connection saturation.

### Part B — Code/IaC
**Answer:**

PostgreSQL lock diagnostic query:

```sql
-- Show current lock holders and waiters with blocking query text.
SELECT
    blocked.pid            AS blocked_pid,
    blocked.usename        AS blocked_user,
    blocked.state          AS blocked_state,
    blocked.query          AS blocked_query,
    blocked_locks.mode     AS blocked_mode,
    blocked_locks.locktype AS blocked_locktype,
    blocking.pid           AS blocking_pid,
    blocking.usename       AS blocking_user,
    blocking.state         AS blocking_state,
    blocking.query         AS blocking_query,
    blocking_locks.mode    AS blocking_mode,
    now() - blocked.xact_start  AS blocked_xact_age,
    now() - blocking.xact_start AS blocking_xact_age
FROM pg_catalog.pg_locks AS blocked_locks
JOIN pg_catalog.pg_stat_activity AS blocked
  ON blocked.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks AS blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
 AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
 AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
 AND blocking_locks.page     IS NOT DISTINCT FROM blocked_locks.page
 AND blocking_locks.tuple    IS NOT DISTINCT FROM blocked_locks.tuple
 AND blocking_locks.virtualxid     IS NOT DISTINCT FROM blocked_locks.virtualxid
 AND blocking_locks.transactionid  IS NOT DISTINCT FROM blocked_locks.transactionid
 AND blocking_locks.classid  IS NOT DISTINCT FROM blocked_locks.classid
 AND blocking_locks.objid    IS NOT DISTINCT FROM blocked_locks.objid
 AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
 AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity AS blocking
  ON blocking.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted
ORDER BY blocked_xact_age DESC;
```

Go circuit breaker with `sony/gobreaker`:

```go
package inventoryclient

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/sony/gobreaker"
)

type Client struct {
	httpClient *http.Client
	baseURL    string
	breaker    *gobreaker.CircuitBreaker
}

type Stock struct {
	SKU      string `json:"sku"`
	Quantity int    `json:"quantity"`
}

func New(baseURL string) *Client {
	settings := gobreaker.Settings{
		Name:        "inventory-service",
		MaxRequests: 5,                // half-open probe requests
		Interval:    60 * time.Second, // rolling window for counts
		Timeout:     30 * time.Second, // open -> half-open cooldown
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			// Open when >=20 requests and failure ratio >= 50%
			if counts.Requests < 20 {
				return false
			}
			ratio := float64(counts.TotalFailures) / float64(counts.Requests)
			return ratio >= 0.5
		},
		OnStateChange: func(name string, from, to gobreaker.State) {
			// Wire to your logger/metrics of choice.
			fmt.Printf("circuit breaker %q: %s -> %s\n", name, from, to)
		},
	}

	return &Client{
		httpClient: &http.Client{Timeout: 500 * time.Millisecond},
		baseURL:    baseURL,
		breaker:    gobreaker.NewCircuitBreaker(settings),
	}
}

// GetStock fetches stock for a SKU. Falls back to a cached/degraded value
// when the breaker is open so checkout can still render.
func (c *Client) GetStock(ctx context.Context, sku string) (*Stock, error) {
	result, err := c.breaker.Execute(func() (interface{}, error) {
		req, err := http.NewRequestWithContext(
			ctx, http.MethodGet, fmt.Sprintf("%s/stock/%s", c.baseURL, sku), nil)
		if err != nil {
			return nil, err
		}

		resp, err := c.httpClient.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()

		if resp.StatusCode >= 500 {
			return nil, fmt.Errorf("inventory-service 5xx: %d", resp.StatusCode)
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("inventory-service status %d", resp.StatusCode)
		}

		var s Stock
		if err := json.NewDecoder(resp.Body).Decode(&s); err != nil {
			return nil, err
		}
		return &s, nil
	})

	if err != nil {
		if errors.Is(err, gobreaker.ErrOpenState) || errors.Is(err, gobreaker.ErrTooManyRequests) {
			// Degraded path: serve last-known-good from local cache, mark response.
			return &Stock{SKU: sku, Quantity: -1}, nil
		}
		return nil, err
	}

	return result.(*Stock), nil
}
```

### Part C — Architecture
**Answer:**
**CQRS + read replica + bulkheads:**

1. **Separate read and write paths.** Introduce a read-only PostgreSQL replica dedicated to the reconciliation job. The CronJob connects only to the replica (set `default_transaction_read_only = on` at role level), so row-level locks never touch the production primary. The reconciliation result is written back via a small idempotent batch at the end, or pushed to a separate audit table.

2. **Bulkhead the connection pool.** Give the CronJob its own PostgreSQL role and connection budget (e.g., `ALTER ROLE reconciler CONNECTION LIMIT 10`), and configure PgBouncer / RDS Proxy pools per role. The serving pods use a different role with its own pool. One workload exhausting its pool cannot starve the other. Inside each service, HikariCP / pgx pool sizes are computed as `num_replicas × pool_size < pg_max_connections × 0.6`.

3. **CQRS for inventory.** Introduce a materialized view or an event-sourced read model (Kafka → read store) so checkout's "is this in stock?" query hits a denormalized store, not the transactional `stock_levels` table. Writes still go to the primary via the inventory-service, but reads scale horizontally and are immune to reconciliation locks.

4. **CronJob scheduling + resource governance.**
   - Move the reconciliation to 03:00 UTC (off-peak). If it must run in business hours, split it into smaller batches (stream through SKUs in chunks of 1,000 with `LIMIT/OFFSET` or keyset pagination) and `pg_sleep(100ms)` between batches.
   - Set `concurrencyPolicy: Forbid` on the CronJob so overruns do not stack.
   - Resource request/limits on the job pod bound to a `ResourceQuota` in a dedicated `batch` namespace so it cannot starve the serving namespace of node capacity.

5. **PodDisruptionBudget and priority:**
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: inventory-service
   spec:
     minAvailable: 80%
     selector:
       matchLabels: { app: inventory-service }
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata: { name: serving }
   value: 1000000
   globalDefault: false
   description: "Serving workloads — protected from preemption."
   ---
   apiVersion: scheduling.k8s.io/v1
   kind: PriorityClass
   metadata: { name: batch }
   value: 100
   description: "Batch CronJobs — preemptible."
   ```
   Serving pods run at the higher PriorityClass; the CronJob uses `batch` and is preempted first under node pressure. The PDB guarantees voluntary disruptions (rolling updates, node drains) cannot take serving capacity below 80%.

6. **Client-side resilience.** The `gobreaker`-based circuit breaker from Part B caps cascading failure and produces predictable checkout behavior (degraded-but-available) when inventory hiccups.

---

## SC6 — Zero-Trust Network Overhaul for a Hybrid Environment

### Part A — Analysis
**Answer:**
**Identity and access layer design:**

**Workload identity (SPIFFE/SPIRE):**
- Deploy **SPIRE servers** in each environment: one in AWS production, one in AWS staging, one on-prem vSphere, one in Azure (if workloads run there). Each SPIRE server is the root of a trust domain (e.g., `prod.aws.example.com`, `onprem.example.com`).
- **SPIRE agents** run on every node (DaemonSet in K8s, systemd unit on VMs) and attest workloads using node + workload attestors (k8s_psat, aws_iid, azure_msi, x509_pop for bare-metal).
- Workloads receive **SPIFFE SVIDs** (X.509 or JWT) via the SPIRE Workload API (`/tmp/spire-agent/public/api.sock`). These SVIDs rotate every ~1 hour and carry a SPIFFE ID like `spiffe://prod.aws.example.com/ns/payments/sa/api`.

**Federation across environments:**
- Configure **SPIFFE federation** between trust domains: each SPIRE server publishes a trust bundle (JWKS) that the other servers fetch over a mutually authenticated channel. A workload in `prod.aws` presenting its SVID to a service in `onprem` can be validated because `onprem`'s SPIRE has the `prod.aws` trust bundle.
- No shared secrets: trust is rooted in SPIRE's attestation of workload identity + federation of public keys.

**Integration with cloud-native IAM:**
- **AWS IAM Roles for SPIFFE:** Use the `AWS_RolesAnywhere` IAM trust anchor backed by SPIRE-issued X.509 SVIDs. A workload exchanges its SVID for temporary AWS credentials via `aws_oidc` assumption. Alternative: project the SPIFFE JWT SVID as a Kubernetes service account token via IRSA (`role-arn` annotation).
- **Azure Managed Identities:** Use Azure Workload Identity federation with the SPIRE-issued JWT as an OIDC issuer. A federated credential on the Azure AD app allows workloads presenting a specific SPIFFE ID to obtain a Managed Identity token.
- **On-prem PKI:** The existing corporate CA remains the trust anchor for human identities and VMware vCenter, but workload certs are issued by SPIRE under a subordinate CA that chains to the corporate root. That way PKI auditing is unified.

**Human identity:** Azure AD is the IdP (SSO via SAML/OIDC) for all consoles — AWS IAM Identity Center (formerly SSO), kubectl via `oidc-login`, vSphere SSO. Human-to-workload calls use short-lived tokens scoped by least-privilege groups.

**Mutual authentication:** Istio or Linkerd in K8s uses SPIFFE SVIDs for mTLS. Outside K8s, envoy-as-sidecar or a service-mesh-native sidecar (Linkerd-jumper, Consul Connect) provides the same on VMs. All service-to-service calls are mTLS-encrypted and authorized via SPIFFE IDs in authorization policies.

**No shared service accounts:** Each workload gets a unique SPIFFE ID and therefore a unique AWS/Azure principal. Policy is authored against SPIFFE IDs, not IPs.

### Part B — Code/IaC
**Answer:**
```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "on_prem_bgp_asn" {
  type    = number
  default = 64512
}

variable "on_prem_vpn_public_ip" {
  type = string
}

variable "privatelink_services" {
  description = "AWS services to expose via PrivateLink (interface endpoints)."
  type        = list(string)
  default = [
    "com.amazonaws.us-east-1.ecr.api",
    "com.amazonaws.us-east-1.ecr.dkr",
    "com.amazonaws.us-east-1.rds",
    "com.amazonaws.us-east-1.secretsmanager",
    "com.amazonaws.us-east-1.logs",
    "com.amazonaws.us-east-1.sts",
  ]
}

# -------- VPC with only private subnets --------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = "zt-prod"
    ZeroTrust = "true"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    for idx, cidr in var.private_subnet_cidrs :
    var.azs[idx] => cidr
  }
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = {
    Name = "zt-prod-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "zt-prod-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# -------- Transit Gateway + VPN --------
resource "aws_ec2_transit_gateway" "this" {
  description                     = "Zero-trust core TGW"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  amazon_side_asn                 = 64513

  tags = { Name = "zt-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  subnet_ids         = [for s in aws_subnet.private : s.id]
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = aws_vpc.this.id

  tags = { Name = "zt-tgw-vpc-attach" }
}

resource "aws_customer_gateway" "on_prem" {
  bgp_asn    = var.on_prem_bgp_asn
  ip_address = var.on_prem_vpn_public_ip
  type       = "ipsec.1"
  tags       = { Name = "zt-onprem-cgw" }
}

resource "aws_vpn_connection" "on_prem" {
  customer_gateway_id = aws_customer_gateway.on_prem.id
  transit_gateway_id  = aws_ec2_transit_gateway.this.id
  type                = "ipsec.1"
  static_routes_only  = false
  tags                = { Name = "zt-onprem-vpn" }
}

# Propagate on-prem routes into the private route table via TGW.
resource "aws_ec2_transit_gateway_route_table_propagation" "on_prem" {
  transit_gateway_attachment_id  = aws_vpn_connection.on_prem.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.this.association_default_route_table_id
}

resource "aws_route" "private_to_tgw" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}

# -------- Default-deny Security Groups --------
resource "aws_security_group" "default_deny" {
  name        = "zt-default-deny"
  description = "Default deny — no ingress, no egress. Attach explicit SGs on top."
  vpc_id      = aws_vpc.this.id

  tags = { Name = "zt-default-deny" }
}

# Endpoint SG — allow only 443 from private subnets.
resource "aws_security_group" "vpc_endpoints" {
  name        = "zt-vpc-endpoints"
  description = "Allow 443 from private subnets to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    description = "Reply traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "zt-vpc-endpoints-sg" }
}

# -------- PrivateLink interface endpoints from variable list --------
resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.privatelink_services)
  vpc_id              = aws_vpc.this.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = replace(each.value, ".", "-")
  }
}

# S3 gateway endpoint (cheaper than interface for S3).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "zt-s3-gw-endpoint" }
}

output "vpc_id" {
  value = aws_vpc.this.id
}
output "tgw_id" {
  value = aws_ec2_transit_gateway.this.id
}
```

### Part C — Architecture
**Answer:**
**Upgrading the 1 Gbps VPN — three options:**

| Option | Bandwidth | Cost (approx) | Encryption | Failover | Fits zero-trust? |
|---|---|---|---|---|---|
| **AWS Direct Connect** (single 10 Gbps port + VIF) | 10 Gbps dedicated, sub-ms jitter | ~$1,600/mo port + $0.02/GB egress | **Not encrypted by default** — must layer MACsec (Dx+ only) or IPsec-over-Dx | Active/standby with a second Dx connection or VPN failover | Encryption must be added; SPIFFE mTLS on top is mandatory |
| **Second VPN tunnel w/ ECMP** | 2 × 1.25 Gbps = ~2.5 Gbps aggregate (TGW ECMP) | Low — TGW attachment + VPN hours | IPsec natively | Automatic via BGP / TGW | Compatible, minimal change |
| **Tailscale / Netbird mesh** | Line-rate per node, WireGuard-based | Per-node licensing (Tailscale Enterprise) | WireGuard (modern ECC, 1-RTT) | Peer-to-peer, no central choke | Excellent — ties identity to device/user via SSO, matches zero-trust model |

**Recommendation:** Go with a hybrid — **Direct Connect for bulk data paths** (S3 replication, database replication, artifact mirrors) and **Tailscale/Netbird for workload-to-workload control-plane traffic**. Reasons:

- Direct Connect alone is not zero-trust: it is unencrypted, and only provides network reachability. You'd still need IPsec or MACsec on top. But its price-per-byte at scale wins for bulk transfer.
- Adding a second VPN tunnel with ECMP doubles bandwidth cheaply and buys time, but 2.5 Gbps is still not enough long term, and it adds no zero-trust value beyond what you already have.
- Tailscale/Netbird is natively zero-trust: device + user identity via OIDC, WireGuard encryption, ACLs authored in JSON referencing tags (not IPs), and peer-to-peer routing that bypasses the VPN concentrator entirely for most traffic. The 1 Gbps VPN stops being the bottleneck because pods talk directly to on-prem hosts over WireGuard.

**Routing architecture changes per option:**
- **Direct Connect:** New Virtual Interface (Transit VIF) attached to the existing Transit Gateway, BGP sessions with on-prem router, 10.0.0.0/8 propagated into TGW route table. Existing VPN kept as warm standby with lower BGP local-pref.
- **ECMP VPN:** Add a second `aws_vpn_connection` to the same TGW, enable `transit_gateway_default_route_table_propagation`, configure BGP equal-cost on the on-prem router. No other changes.
- **Tailscale/Netbird:** Deploy a Tailscale subnet router on-prem and in each AWS VPC (2–3 HA replicas), publish each environment's CIDRs via `--advertise-routes`. ACLs in Tailscale control plane replace large parts of the Security Group matrix. The existing VPN stays for break-glass only. Routing table: pods route to 10.0.0.0/8 via a `tailscale0` interface injected by the subnet router.

Final answer: for a zero-trust mandate with a 1 Gbps ceiling today, **add Direct Connect (10 Gbps) + MACsec/IPsec-on-Dx for bulk traffic, plus Tailscale for workload mesh identity**, and retire the VPN to cold standby. Cost rises, but you get 10× bandwidth, cryptographic identity, and a much smaller attack surface.

---

## SC7 — CI/CD Pipeline Causing Production Drift

### Part A — Analysis
**Answer:**
**Three drift sources explained:**

1. **14 manual `tofu apply` from laptops.** Each laptop has different local state cache, different provider versions, and possibly different `.tfvars`. Without state locking, concurrent applies race; the loser's changes overwrite the winner's `terraform.tfstate` when pushed back to S3. Resources can be orphaned (created in cloud but missing from state), or destroyed unintentionally (engineer A's plan computed against stale state deletes something engineer B just created). Without S3 versioning you cannot even roll back to a prior good state.

2. **Divergent Helm values files.** If `staging/values.yaml` and `production/values.yaml` are both hand-edited without sharing a base, any change made to staging to fix an incident may never propagate to production, and vice versa. Values drift silently; reviewers cannot tell by reading a PR whether a change matches what is already running.

3. **`kubectl edit` on production ConfigMaps.** Direct edits bypass Git entirely. A pod restart may pick up new values, but the next `helm upgrade` reverts them silently, causing mysterious incidents. There is no audit trail of who changed what and why.

**Two engineers running `tofu apply` concurrently on the same state:** Both read the state file at time T. Engineer A computes a plan and writes a new state file at T+30s. Engineer B (whose plan was computed against the old state) writes their new state file at T+35s, overwriting A's state entirely. Resources A created are now orphaned: they exist in AWS but are missing from state, so the next plan will either try to re-create them (error: "already exists") or destroy them. **State corruption can also happen mid-write** if both processes are writing simultaneously with no lock; you can end up with truncated JSON that Terraform refuses to parse. With no versioning, you cannot recover the prior state, and you will be manually importing resources for a day.

Specific data-loss/outage scenarios:
- Terraform thinks an RDS instance doesn't exist and tries to create a new one with the same name → fails with `DBInstanceAlreadyExists`. Pipeline breaks.
- Terraform thinks a security group doesn't exist and tries to destroy dependent resources, taking down production traffic.
- State is corrupted; every subsequent plan fails until restored from ... nothing, because versioning is off.

### Part B — Code/IaC
**Answer:**
```yaml
# .gitlab-ci.yml
stages:
  - validate
  - plan
  - apply

variables:
  TF_ROOT: infra
  TF_VERSION: "1.7.4"
  TF_IN_AUTOMATION: "true"
  AWS_REGION: us-east-1
  TF_STATE_BUCKET: myorg-tf-state
  TF_LOCK_TABLE: myorg-tf-locks

.tofu:
  image: ghcr.io/opentofu/opentofu:${TF_VERSION}
  before_script:
    - cd "${TF_ROOT}/${TF_WORKSPACE}"
    - |
      tofu init \
        -backend-config="bucket=${TF_STATE_BUCKET}" \
        -backend-config="key=${TF_WORKSPACE}/terraform.tfstate" \
        -backend-config="region=${AWS_REGION}" \
        -backend-config="dynamodb_table=${TF_LOCK_TABLE}" \
        -backend-config="encrypt=true"

fmt_validate:
  stage: validate
  extends: .tofu
  parallel:
    matrix:
      - TF_WORKSPACE: [dev, staging, production]
  script:
    - tofu fmt -check -recursive
    - tofu validate

plan_dev:
  stage: plan
  extends: .tofu
  variables:
    TF_WORKSPACE: dev
  environment:
    name: dev
    action: prepare
  script:
    - tofu plan -out=tfplan.bin -no-color | tee tfplan.txt
    - |
      if [ -n "${CI_MERGE_REQUEST_IID:-}" ]; then
        jq -Rn --arg body "$(printf '### OpenTofu plan (dev)\n\n```\n%s\n```' "$(cat tfplan.txt)")" '{body: $body}' > comment.json
        curl --fail --silent --show-error \
          --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" \
          --header "Content-Type: application/json" \
          --data @comment.json \
          "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/merge_requests/${CI_MERGE_REQUEST_IID}/notes"
      fi
  artifacts:
    paths:
      - ${TF_ROOT}/dev/tfplan.bin
      - ${TF_ROOT}/dev/tfplan.txt
    expire_in: 1 week
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"

plan_staging:
  stage: plan
  extends: .tofu
  variables:
    TF_WORKSPACE: staging
  environment:
    name: staging
    action: prepare
  script:
    - tofu plan -out=tfplan.bin -no-color | tee tfplan.txt
  artifacts:
    paths:
      - ${TF_ROOT}/staging/tfplan.bin
      - ${TF_ROOT}/staging/tfplan.txt
    expire_in: 1 week
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"

plan_production:
  stage: plan
  extends: .tofu
  variables:
    TF_WORKSPACE: production
  environment:
    name: production
    action: prepare
  script:
    - tofu plan -out=tfplan.bin -no-color -detailed-exitcode | tee tfplan.txt
  artifacts:
    paths:
      - ${TF_ROOT}/production/tfplan.bin
      - ${TF_ROOT}/production/tfplan.txt
    expire_in: 1 week
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"

apply_dev:
  stage: apply
  extends: .tofu
  variables:
    TF_WORKSPACE: dev
  environment:
    name: dev
    action: start
  needs: [plan_dev]
  script:
    - tofu apply -auto-approve tfplan.bin
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

apply_staging:
  stage: apply
  extends: .tofu
  variables:
    TF_WORKSPACE: staging
  environment:
    name: staging
    action: start
  needs: [plan_staging]
  script:
    - tofu apply -auto-approve tfplan.bin
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

apply_production:
  stage: apply
  extends: .tofu
  variables:
    TF_WORKSPACE: production
  environment:
    name: production
    action: start
  needs: [plan_production]
  when: manual
  allow_failure: false
  script:
    - tofu apply -auto-approve tfplan.bin
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
```

Key points:
- DynamoDB table (`myorg-tf-locks`) provides state locking via the S3 backend.
- `tofu fmt -check` and `tofu validate` gate every MR.
- Plans are posted back as MR notes via the GitLab API.
- `apply_production` is `when: manual` with `allow_failure: false`, so a human must explicitly click to proceed.
- `environment.name` lets GitLab track deployment history and enforce protected-environment rules in project settings (which is where you configure "only maintainers can trigger apply_production").

### Part C — Architecture
**Answer:**
**Drift detection and reconciliation system:**

1. **Scheduled drift detection.** A GitLab scheduled pipeline (`schedule: "0 */4 * * *"`) runs `tofu plan -detailed-exitcode` against each environment. Exit code `2` means drift detected; the job opens (or updates) a GitLab issue titled `drift: <env>` with the plan output, pages on-call via Alertmanager webhook, and labels the issue by severity (number of resource changes). Slack bot posts a summary.

2. **Kubernetes-side drift prevention.** Install **Kyverno** (or OPA Gatekeeper) with a cluster policy:
   ```yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata: { name: block-direct-configmap-edits }
   spec:
     validationFailureAction: Enforce
     rules:
       - name: no-direct-edit-of-managed
         match:
           any:
             - resources:
                 kinds: [ConfigMap, Secret]
                 selector:
                   matchLabels:
                     app.kubernetes.io/managed-by: Helm
         exclude:
           any:
             - subjects:
                 - kind: ServiceAccount
                   name: gitlab-runner
                   namespace: cicd
         validate:
           message: "Direct edits to Helm-managed resources are forbidden; change values in Git."
           deny: {}
   ```
   Any `kubectl edit` from a user identity is rejected; only the `gitlab-runner` SA bypasses the rule. A `MutatingWebhook` can additionally stamp `last-applied-by` annotations for auditability.

3. **Helm values structure with shared base.** Use **Helmfile** with a base values file and per-environment overlays:
   ```yaml
   # helmfile.yaml
   releases:
     - name: api-gateway
       chart: charts/api-gateway
       values:
         - values/base.yaml
         - values/{{ .Environment.Name }}.yaml
       set:
         - name: image.tag
           value: {{ .Values.imageTag }}
   environments:
     dev:       { values: [environments/dev.yaml] }
     staging:   { values: [environments/staging.yaml] }
     production:{ values: [environments/production.yaml] }
   ```
   Or equivalently with Kustomize: a `base/` and `overlays/{dev,staging,production}/` tree, where production is a patch on top of base, not a full copy. Diffs between environments become reviewable one-liners.

4. **RBAC — only the CI service account has write access.**
   - **Kubernetes:** remove `edit`/`admin` ClusterRoleBinding from human users; grant them `view` only. Create `gitlab-runner` ServiceAccount with the necessary namespace-scoped roles (`Role`: get/list/watch/create/update/patch/delete on Deployment, Service, ConfigMap, Secret; no cluster-admin).
   - **AWS:** Delete IAM user access keys for engineers. Developers log in via IAM Identity Center (SSO) with read-only roles. Write operations happen only through a `gitlab-runner` IAM role assumed via OIDC federation from GitLab (`sts:AssumeRoleWithWebIdentity`); trust policy scoped by repository and branch claims.
   - **Tofu state S3 bucket:** Bucket policy allows only the CI role to `s3:PutObject`/`s3:DeleteObject`; engineers get `s3:GetObject` for reading plans. Turn on S3 versioning and object lock so state can be rolled back.
   - **Break-glass:** emergency role that requires MFA + PagerDuty approval, audited via CloudTrail.

5. **Audit layer.** CloudTrail → EventBridge → SNS alerts on any API call not originating from the CI role; Kubernetes audit logs forwarded to Loki with alerts on write actions from non-CI identities.

---

## SC8 — Observability Stack Scaling Failure

### Part A — Analysis
**Answer:**
**Symptom 1: Prometheus OOM every 4 hours at 64GB RAM.**
Root cause: 8.2 M active series is far above what a single Prometheus can hold in memory. Each active series costs roughly 3–5 KB of RAM for head block, label indexes, and WAL. 8.2 M × 4 KB ≈ 32 GB just for series data, plus query evaluation, ingestion buffers, and the ~2h head block. The 4-hour cadence aligns with head-block rotation and WAL truncation spikes.
Checks: `prometheus_tsdb_head_series`, `prometheus_tsdb_head_chunks`, `process_resident_memory_bytes`, `go_memstats_heap_inuse_bytes`, `rate(prometheus_tsdb_head_samples_appended_total[5m])`. Use `topk(20, count by (__name__)({__name__=~".+"}))` to find the highest-cardinality metric names. For a specific metric, `topk(20, count by (label) (metric_name))` identifies the offending label.

**High cardinality** means a metric has many unique label-value combinations, each producing a distinct time series. Typical causes: user IDs, request IDs, full URL paths, or unbounded labels (HTTP status where every 4xx has a specific reason). Each unique combination is a time series Prometheus must track. A single metric with `user_id` as a label can explode to millions of series.

**Symptom 2: Loki ingester dropping 15% of log lines at peak.**
Root cause: Ingester rate limits (`ingestion_rate_mb`, `ingestion_burst_size_mb`) or per-stream limits (`max_streams_per_user`, `max_line_size`) are being hit. With monolithic Loki on a small cluster, a single ingester's backpressure causes drops — symptom is `loki_discarded_samples_total` and HTTP 429s in the distributor.
Checks: `loki_discarded_samples_total`, `loki_request_duration_seconds_bucket{route="loki_api_v1_push"}`, `loki_ingester_memory_streams`, `loki_distributor_ingester_append_failures_total`.

**Symptom 3: Tempo queries for traces older than 2 hours timing out.**
Root cause: Tempo is running with the local backend (or with S3 but undersized queriers/query-frontend), so spans older than the in-memory/WAL window require block scanning. With only 2h of accessible history, the block cache is tiny and bloom filters are ineffective. Also indicates the block format or compaction is suboptimal for age-based queries.
Checks: `tempo_request_duration_seconds_bucket{route="querier"}`, `tempo_query_frontend_queries_total{status="failed"}`, `tempo_ingester_blocks_flushed_total`, `tempodb_backend_request_duration_seconds_bucket`.

**Symptom 4: Thanos compactor 3 days behind.**
Root cause: Single-instance compactor cannot keep up with 8.2 M series × 40 teams × block churn. With 14 TB in S3 growing 500 GB/week, the compactor has to download, compact, and re-upload blocks faster than new blocks arrive; a single compactor pod is CPU/bandwidth-bound. Also suggests missing downsampling (5m / 1h resolution) so queries cost more than necessary.
Checks: `thanos_compact_group_compactions_total`, `thanos_compact_halted`, `thanos_compact_iterations_total`, `thanos_objstore_bucket_last_successful_upload_time`, compactor pod CPU and network I/O.

### Part B — Code/IaC
**Answer:**
```bash
#!/usr/bin/env bash
# cardinality-report.sh — Prometheus cardinality report for Slack.
set -euo pipefail

PROM_URL="${PROM_URL:-http://prometheus.monitoring.svc:9090}"
TOP_N="${TOP_N:-20}"

command -v jq   >/dev/null || { echo "jq required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }

api() {
  local path="$1"
  curl -fsSL --get --data-urlencode "query=${2:-}" "${PROM_URL}${path}"
}

echo "== Gathering metric names =="
NAMES_JSON=$(curl -fsSL "${PROM_URL}/api/v1/label/__name__/values")
TOTAL_NAMES=$(echo "${NAMES_JSON}" | jq '.data | length')

echo "Fetching series counts for each metric (this can take a few minutes)..."
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT

echo "${NAMES_JSON}" | jq -r '.data[]' | while IFS= read -r name; do
  # Count series for each metric with a single instant query.
  count=$(curl -fsSL --get \
    --data-urlencode "query=count({__name__=\"${name}\"})" \
    "${PROM_URL}/api/v1/query" \
    | jq -r '.data.result[0].value[1] // "0"')
  printf '%s\t%s\n' "${count}" "${name}" >> "${tmp}"
done

sort -k1 -n -r "${tmp}" > "${tmp}.sorted"

TOP_METRIC=$(head -n1 "${tmp}.sorted" | awk '{print $2}')
TOP_COUNT=$(head -n1 "${tmp}.sorted"  | awk '{print $1}')

# For the top metric, find the label with the most unique values.
TOP_LABEL=""
TOP_LABEL_CARDINALITY=0
LABELS=$(curl -fsSL "${PROM_URL}/api/v1/labels" | jq -r '.data[]')
for lbl in ${LABELS}; do
  [[ "${lbl}" == "__name__" ]] && continue
  c=$(curl -fsSL --get \
    --data-urlencode "query=count(count by (${lbl}) ({__name__=\"${TOP_METRIC}\"}))" \
    "${PROM_URL}/api/v1/query" \
    | jq -r '.data.result[0].value[1] // "0"')
  if (( c > TOP_LABEL_CARDINALITY )); then
    TOP_LABEL_CARDINALITY="${c}"
    TOP_LABEL="${lbl}"
  fi
done

# Render Slack-friendly report.
{
  printf '```\n'
  printf 'Prometheus Cardinality Report\n'
  printf '=============================\n'
  printf 'Endpoint              : %s\n' "${PROM_URL}"
  printf 'Unique metric names   : %s\n' "${TOTAL_NAMES}"
  printf 'Highest-cardinality   : %s  (%s series)\n' "${TOP_METRIC}" "${TOP_COUNT}"
  printf 'Worst label on above  : %s  (%s unique values)\n' "${TOP_LABEL}" "${TOP_LABEL_CARDINALITY}"
  printf '\n'
  printf 'Top %s metrics by series count\n' "${TOP_N}"
  printf '%-12s  %s\n' "SERIES" "METRIC"
  printf '%-12s  %s\n' "------" "------"
  head -n "${TOP_N}" "${tmp}.sorted" | awk '{printf "%-12s  %s\n", $1, $2}'
  printf '```\n'
} | tee cardinality-report.txt
```

### Part C — Architecture
**Answer:**
**Target: 50 M active series, 200 teams.**

1. **Metrics tier — replace single Prometheus + Thanos with Mimir (or VictoriaMetrics cluster).**
   - **Grafana Mimir** deployed in microservices mode: distributor, ingester (replication factor 3), querier, query-frontend, compactor, store-gateway. Each component scales independently. Ingesters shard by tenant + series hash.
   - Multi-tenancy is first-class: every team is a tenant (`X-Scope-OrgID`), with per-tenant limits on `max_global_series_per_user`, `ingestion_rate`, and query concurrency. A runaway team cannot starve others.
   - Prometheus agents (or Grafana Agent Flow, now Alloy) on each cluster remote-write to Mimir. Agents do the scraping; Mimir does storage.
   - Backend: S3 for long-term, with 5m and 1h downsampling via the compactor. 50 M series with good downsampling fits in well-provisioned Mimir ingesters (shard per tenant keeps any single ingester manageable).
   - Alternative: **VictoriaMetrics cluster** (`vminsert`, `vmstorage`, `vmselect`). Simpler to operate, lower memory per series, excellent for high cardinality. Picks the same conceptual slot.

2. **Logs tier — Loki in microservices mode.**
   - Split into distributor, ingester, querier, query-frontend, ruler, compactor, index-gateway. Read and write paths scale independently.
   - Use **TSDB index** (not boltdb-shipper) and S3 for chunks.
   - Per-tenant rate limits (`ingestion_rate_mb`, `max_streams_per_user`, `max_line_size_bytes`) in `overrides.yaml`.
   - Client-side log sampling in Alloy for chatty apps.

3. **Traces tier — Tempo with S3 backend, proper read/write split.**
   - Distributors, ingesters, queriers, query-frontend, compactor as separate deployments.
   - Backend: S3 with WAL on local PVCs for ingesters.
   - Tail-based sampling in Alloy or OpenTelemetry Collector so we only ship the interesting 5–10% of traces.
   - Bloom filters + Parquet block format (Tempo 2.x) for fast time-range queries beyond 2h.
   - TraceQL for correlated lookups instead of full scans.

4. **Governance & cardinality limits.**
   - **Per-tenant limits** in Mimir's runtime config; changes via GitOps.
   - **Relabeling rules** at the Alloy scraper level: drop high-cardinality labels at source (`action: labeldrop` on `pod_template_hash`, `controller_revision_hash`, full URL paths, user IDs). Block `/metrics` endpoints that have not passed a cardinality lint.
   - **Recording rules** to pre-aggregate expensive queries (team dashboards read a 1-minute recording rule, not raw series). Move common queries from ad-hoc to rule-based.
   - **Cardinality CI gate:** a pre-merge job runs the service's metrics through `promlint` and a cardinality estimator; blocks merges that would add >10 k series for a single metric.
   - **Teams get dashboards and alerts showing their own cardinality consumption**, published as SLOs.

5. **Chargeback.**
   - Mimir / Loki / Tempo emit per-tenant metrics (`cortex_ingester_memory_series{user="team-a"}`, `loki_ingester_memory_streams{tenant="team-a"}`, `tempo_distributor_bytes_received_total`). A nightly job sums these per tenant.
   - Storage cost attribution: S3 bucket prefixed `mimir/team-a/...` (via tenant federation) and `aws s3 ls --summarize` per prefix → cost per team.
   - Compute cost: total Mimir cluster cost × (team's ingested samples / total ingested samples) + a fixed "platform overhead" share.
   - Monthly report dashboards published to each team, and a hard cap after N% of a team's budget (they must ask platform to raise the limit).
   - Finance integration: export monthly chargeback CSV into the company's cost-center system.

6. **Observability of observability.** Run a small "meta" Prometheus that scrapes the whole stack (Mimir, Loki, Tempo, Alloy). Alerts on ingester saturation, compactor lag, S3 bucket growth, and per-tenant limit breaches.

---

## SC9 — Securing a Public-Facing API After a Breach

### Part A — Analysis
**Answer:**

1. **BOLA (Broken Object Level Authorization).**
   - OWASP API Top 10: **API1:2023 — Broken Object Level Authorization.** Principle violated: access control must verify the authenticated subject is authorized for the specific object, not just authenticated.
   - Blast radius: any authenticated user can enumerate and exfiltrate every record in the system by iterating IDs. In a Django app with user records, this is essentially full database read. Combined with weak rate limiting (issue 3), an attacker extracts the entire user table in minutes.
   - Fix: enforce ownership at the ORM query level, not at the view filter level. Always scope queries by `request.user` (or the user's tenant). Prefer UUIDs to sequential IDs so enumeration is harder, but UUIDs are defense-in-depth, not a fix.
   - DRF code:
     ```python
     from rest_framework import generics, permissions, exceptions
     from .models import Record
     from .serializers import RecordSerializer

     class IsOwner(permissions.BasePermission):
         def has_object_permission(self, request, view, obj):
             return obj.owner_id == request.user.id

     class RecordDetail(generics.RetrieveUpdateDestroyAPIView):
         serializer_class = RecordSerializer
         permission_classes = [permissions.IsAuthenticated, IsOwner]

         def get_queryset(self):
             # Scope to owner at the query level — belt-and-braces.
             return Record.objects.filter(owner=self.request.user)

         def get_object(self):
             obj = super().get_object()  # runs get_queryset().get(pk=...)
             self.check_object_permissions(self.request, obj)
             return obj
     ```
     The combination of (a) `get_queryset` scoped to the user and (b) `check_object_permissions` via `IsOwner` guarantees an attacker changing the URL ID either gets 404 (not in queryset) or 403 (object permission fails).

2. **Mass assignment / overly broad serializer output.**
   - OWASP API Top 10: **API3:2023 — Broken Object Property Level Authorization** (formerly "Excessive Data Exposure" and "Mass Assignment").
   - Blast radius: leaking `created_by_employee_id` exposes internal org structure; `internal_notes` may contain compliance/PII/legal. Useful for social engineering and insider-risk targeting.
   - Fix: define explicit `fields` (allowlist) on the `ModelSerializer`, never use `fields = '__all__'`. Separate read and write serializers where they differ:
     ```python
     class RecordSerializer(serializers.ModelSerializer):
         class Meta:
             model = Record
             fields = ['id', 'title', 'amount', 'created_at']  # explicit allowlist
             read_only_fields = ['id', 'created_at']
     ```

3. **No rate limiting — 100 k records in 10 minutes.**
   - OWASP API Top 10: **API4:2023 — Unrestricted Resource Consumption.**
   - Blast radius: full data exfiltration, DoS, runaway cost. With BOLA unpatched, this is a direct "dump the database" scenario.
   - Fix: layered rate limiting — at the edge (WAFv2 / API Gateway), at the application (DRF `DEFAULT_THROTTLE_CLASSES` with `ScopedRateThrottle`), and per-object with leaky-bucket counters in Redis. WAF rules limit by source IP; app throttles limit by authenticated user/JWT sub.

4. **API keys in URL query parameters.**
   - OWASP API Top 10: **API8:2023 — Security Misconfiguration** (and API2 — Broken Auth).
   - Blast radius: API keys are logged in CloudWatch, ALB access logs, browser history, upstream CDN logs, and can be seen by anyone with read access to logs. Effectively every API key is compromised.
   - Fix: move authentication to the `Authorization: Bearer ...` header (which is never in query strings), rotate all API keys immediately, and purge/redact existing log data. Add ALB access log field masking or CloudWatch log filter pattern to scrub any residual occurrences. Prefer OAuth2 + JWT with short TTL.

### Part B — Code/IaC
**Answer:**
```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

variable "alb_arn" {
  type        = string
  description = "ARN of the ALB to associate with the WAF web ACL."
}

variable "allowed_country_codes" {
  type        = list(string)
  description = "ISO 3166-1 alpha-2 country codes where the business operates."
  default     = ["US", "CA", "GB", "DK", "DE"]
}

resource "aws_wafv2_web_acl" "api" {
  name        = "api-public-acl"
  description = "Zero-trust edge rules for the public REST API."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # 1. Rate limit — 100 requests per 5 minutes per IP.
  rule {
    name     = "rate-limit-per-ip"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
        evaluation_window_sec = 300
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit-per-ip"
    }
  }

  # 2. Block requests where api_key appears in the query string.
  rule {
    name     = "block-api-key-in-query-string"
    priority = 20

    action {
      block {}
    }

    statement {
      byte_match_statement {
        positional_constraint = "CONTAINS"
        search_string         = "api_key="

        field_to_match {
          query_string {}
        }

        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }

        text_transformation {
          priority = 1
          type     = "URL_DECODE"
        }
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "block-api-key-in-query-string"
    }
  }

  # 3. AWS Managed Rules — common web exploits (SQLi, XSS, etc.).
  rule {
    name     = "aws-managed-common"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-managed-common"
    }
  }

  # 3b. AWS Managed Rules — known bad inputs (SQLi, LFI, RFI).
  rule {
    name     = "aws-managed-sqli"
    priority = 31

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "aws-managed-sqli"
    }
  }

  # 4. Geo-block — allow only business countries.
  rule {
    name     = "geo-allowlist"
    priority = 40

    action {
      block {}
    }

    statement {
      not_statement {
        statement {
          geo_match_statement {
            country_codes = var.allowed_country_codes
          }
        }
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "geo-allowlist"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "api-public-acl"
  }

  tags = {
    Name = "api-public-acl"
  }
}

resource "aws_wafv2_web_acl_association" "api_alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}
```

### Part C — Architecture
**Answer:**
**Defense-in-depth target architecture:**

1. **Edge — API Gateway in front of ALB.** Put **AWS API Gateway (HTTP API)** or **Kong** in front of the ALB. The gateway centralizes authentication, rate limiting, request transformation, and request validation (OpenAPI schema enforcement). The ALB becomes an origin the gateway speaks to privately (PrivateLink or VPC link).

2. **Authentication — OAuth2 + short-lived JWTs.**
   - Introduce an IdP (Auth0, Okta, Cognito, or Keycloak) as the OAuth2 Authorization Server.
   - Clients obtain a short-lived (5–15 min) JWT access token via `client_credentials` (machine) or `authorization_code + PKCE` (interactive).
   - The API Gateway verifies the JWT signature against the IdP's JWKS, validates `aud`, `iss`, `exp`, and extracts `sub`/`scope` claims into headers the backend can trust.
   - JWTs go in `Authorization: Bearer ...` — never in query strings.
   - Refresh tokens are stored in httpOnly secure cookies (interactive) or server-side (machine).

3. **Migration from API keys to OAuth2 without breaking consumers.**
   - Phase 1: Rotate all existing API keys immediately; issue new ones via the **header**, not the query string. Redeploy app to accept both `Authorization: ApiKey xxx` header and the legacy query param, but log a deprecation warning for the latter. Set a hard sunset date (e.g., 90 days).
   - Phase 2: Stand up the IdP, publish OAuth2 client onboarding docs, and provide a compatibility shim at the API Gateway that accepts the legacy `Authorization: ApiKey xxx` header and mints a short-lived JWT internally (gateway → IdP token exchange or local JWT signing with the gateway's private key). Consumers can migrate at their pace.
   - Phase 3: Monitor usage of legacy auth via gateway metrics; nudge remaining consumers, then disable the legacy header on the sunset date.
   - Phase 4: Remove the legacy code path from the Django app entirely.

4. **Authorization at the application layer.** Keep the DRF `IsOwner` + queryset scoping pattern from Part A. JWT claims provide `sub`; the app enforces that `Record.objects.filter(owner_id=request.user.id)` is the only query path. Object-level permissions are **never** the only defense — the query must also be scoped.

5. **Rate limiting — layered.**
   - WAF: 100 req / 5min per IP (edge, untrusted).
   - API Gateway: 1,000 req/min per authenticated subject (usage plans keyed by JWT `sub`).
   - Django `ScopedRateThrottle`: 100 req/min per authenticated user on expensive endpoints.
   - Redis-backed leaky bucket for per-object write rate limiting.

6. **Audit logging.** Enable **CloudTrail data events** for the S3 buckets backing the API, ALB access logs to a dedicated log bucket with **object lock**, and API Gateway execution logs (WARN level). All logs ship to a separate security account (log archive account) with read-only IAM roles for the SOC. Correlate via a unique `x-request-id` header added at the gateway.

7. **PII protection — field-level encryption.** For the `internal_notes`, PII fields, and any sensitive columns, use **application-level envelope encryption**: encrypt with a per-tenant data key (DK) stored in Secrets Manager or KMS; the DK is wrapped by a KMS CMK. The database stores only ciphertext + key ID. A SQL dump leak yields nothing without KMS access. Implement via a Django custom field (`EncryptedTextField`) backed by `cryptography.fernet` with KMS-held keys.

8. **Secrets and key rotation.** All API keys, JWT signing keys, and database credentials are managed via AWS Secrets Manager with automatic rotation enabled. The application reads secrets at startup via IAM role (IRSA), not from env vars or config files.

9. **WAF + GuardDuty + Inspector** run continuously; alerts fire to PagerDuty on new WAF rule hits or GuardDuty findings.

10. **Tabletop exercise and red team.** Schedule a red-team engagement 30 days after rollout to verify all four findings are closed and that no new BOLA / rate-limit / auth bypass paths exist.

---

## SC10 — Designing a Multi-Cluster Disaster Recovery Platform

### Part A — Analysis
**Answer:**
**Requirements:** RPO ≤ 15 min, RTO ≤ 1 hour, two DCs (Chicago primary, Dallas DR), 12ms latency, 10 Gbps dark fiber, 200 TB MinIO.

**Option 1 — Active/passive with Velero backup/restore.**
- Velero takes scheduled backups of Kubernetes resources + PV snapshots to object storage (could be MinIO itself, replicated to Dallas).
- On failure: spin up workloads in the Dallas cluster from the latest backup.
- **RPO analysis:** Velero default schedule is hourly. To hit RPO ≤ 15 min you'd run it every 10 min, which is feasible for resource state but **not** for 200 TB PV data. Volume snapshots of 200 TB cannot complete in 15 min even over 10 Gbps (ideal throughput: ~1.25 GB/s, so 200 TB = ~44 hours for a full snapshot; incremental snapshots via CSI are much faster but still bounded by block change rate).
- **RTO analysis:** resource restore is minutes. PV restore from snapshot is hours-to-days for 200 TB. **Fails the 1-hour RTO** unless underlying storage replication is continuous (not Velero's job).
- Conclusion: Velero alone does NOT meet requirements. It works for configuration state + application backup, but the data plane needs continuous replication.

**Option 2 — Active/active with Istio multi-cluster or Cilium Cluster Mesh.**
- Both clusters run the workloads; the service mesh cross-cluster routes traffic. With a shared IdP and mTLS via mesh certs, services in Chicago can call services in Dallas transparently.
- **Istio multi-cluster (primary-primary):** both clusters have a control plane, share a root CA, and use endpoint discovery to see services across clusters. Failover is DNS/GSLB-driven and near-instant.
- **Cilium Cluster Mesh:** similar semantics, uses eBPF and Hubble; lower data-plane overhead than Istio.
- **RPO analysis:** For stateless workloads, RPO is effectively zero. For stateful workloads, RPO is bounded by the replication strategy of each data store, not by the mesh.
- **RTO analysis:** failover time is bounded by (failure-detection + DNS TTL + data-store promotion). With 30s health checks, 10s DNS TTL, and 60s Patroni promotion, RTO is ~2–3 min. **Well within 1 hour.**

**Recommendation:** Active/active with service mesh **for stateless workloads and for reads**, with per-component replication for stateful layers. Pure active/active writes are not realistic for PostgreSQL at 12ms RTT with synchronous replication (latency budget) — so writes stay in the current primary site, reads serve locally from a replica. On failure, the standby is promoted.

**Replication strategy per component:**

| Component | Strategy | RPO | RTO |
|---|---|---|---|
| **PostgreSQL (Patroni)** | Synchronous streaming replication with `synchronous_commit = remote_apply` (acceptable at 12ms), one sync replica in Dallas + one async, replication slots, Patroni over etcd across sites. Promotion via Patroni REST API. | ~0 (sync) | ~60s |
| **Redis** | Redis Sentinel with replicas in both sites, cluster of 3 sentinels per DC (odd total 5+, avoid split-brain). For higher data guarantee, Redis Enterprise CRDBs or Keydb with active-replica. | Sub-second | ~30s |
| **RabbitMQ** | Quorum queues replicated across the cluster spanning both sites, OR federation/shovel for cross-site + mirrored classic queues. Prefer **quorum queues** (Raft-based, tolerate site failure). | ~0 (Raft sync) | ~30s |
| **MinIO** | **MinIO site replication** (active-active bucket replication) built-in. With 10 Gbps dark fiber at 12ms, steady-state replication lag is seconds to minutes for hot data; catch-up after outage depends on change rate. | Minutes typical; bounded by 500 GB/week growth | N/A for reads (both live) |
| **Kubernetes manifests** | GitOps via Argo CD/Flux, both clusters reconcile from the same Git repo. | 0 | Instant |
| **Secrets** | External Secrets Operator fronting HashiCorp Vault with Raft storage replicated across sites, or SealedSecrets in Git. | 0 | Instant |

**For MinIO 200 TB specifically:** MinIO site replication is the only viable strategy. Velero snapshots would never finish in time. Site replication is near-continuous and the 10 Gbps fiber supports the 500 GB/week growth rate easily (that's ~10 MB/s average). Peak bursts are the risk — monitor `minio_bucket_replication_pending_count`.

**RPO/RTO verdict:** With this hybrid (active/active mesh + per-component replication), RPO ~ seconds for all components, RTO ~ 2–5 minutes, well inside the regulatory 15-min RPO / 1-hour RTO.

### Part B — Code/IaC
**Answer:**
```yaml
# inventories/production.yml  (excerpt)
# all:
#   children:
#     patroni:
#       hosts:
#         pg-chi-01: { ansible_host: 10.10.1.11 }
#         pg-chi-02: { ansible_host: 10.10.1.12 }
#         pg-dal-01: { ansible_host: 10.20.1.11 }
#         pg-dal-02: { ansible_host: 10.20.1.12 }
#     etcd:
#       hosts:
#         etcd-chi-01: { ansible_host: 10.10.2.11 }
#         etcd-chi-02: { ansible_host: 10.10.2.12 }
#         etcd-dal-01: { ansible_host: 10.20.2.11 }
#         etcd-dal-02: { ansible_host: 10.20.2.12 }
#         etcd-arb-01: { ansible_host: 10.30.2.11 }  # tiebreaker / witness

---
# playbook: patroni.yml
- name: Configure etcd DCS for Patroni
  hosts: etcd
  become: true
  gather_facts: true
  vars:
    etcd_version: "3.5.12"
    etcd_cluster_token: "patroni-dcs"
    etcd_client_port: 2379
    etcd_peer_port: 2380
  tasks:
    - name: Install dependencies
      ansible.builtin.apt:
        name:
          - curl
          - ca-certificates
          - gnupg
        state: present
        update_cache: true

    - name: Create etcd user
      ansible.builtin.user:
        name: etcd
        system: true
        shell: /usr/sbin/nologin
        home: /var/lib/etcd
        create_home: false

    - name: Create etcd directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: etcd
        group: etcd
        mode: "0750"
      loop:
        - /var/lib/etcd
        - /etc/etcd

    - name: Download etcd binary
      ansible.builtin.get_url:
        url: "https://github.com/etcd-io/etcd/releases/download/v{{ etcd_version }}/etcd-v{{ etcd_version }}-linux-amd64.tar.gz"
        dest: "/tmp/etcd-v{{ etcd_version }}.tar.gz"
        mode: "0644"

    - name: Extract etcd
      ansible.builtin.unarchive:
        src: "/tmp/etcd-v{{ etcd_version }}.tar.gz"
        dest: /usr/local/bin
        remote_src: true
        extra_opts:
          - "--strip-components=1"
          - "--wildcards"
          - "*/etcd"
          - "*/etcdctl"
        creates: "/usr/local/bin/etcd"

    - name: Template etcd systemd unit
      ansible.builtin.template:
        src: etcd.service.j2
        dest: /etc/systemd/system/etcd.service
        mode: "0644"
      notify: restart etcd

    - name: Enable and start etcd
      ansible.builtin.systemd:
        name: etcd
        daemon_reload: true
        enabled: true
        state: started

  handlers:
    - name: restart etcd
      ansible.builtin.systemd:
        name: etcd
        state: restarted

- name: Install and configure Patroni
  hosts: patroni
  become: true
  gather_facts: true
  vars:
    postgres_version: 16
    patroni_scope: "pg-global"
    patroni_data_dir: "/var/lib/postgresql/{{ postgres_version }}/main"
    patroni_bin_dir: "/usr/lib/postgresql/{{ postgres_version }}/bin"
    etcd_endpoints: >-
      {{ groups['etcd'] | map('extract', hostvars, ['ansible_host'])
         | map('regex_replace', '^(.*)$', 'http://\1:2379') | list | join(',') }}
    patroni_sync_standby_names: "pg-dal-01"
  tasks:
    - name: Install PostgreSQL and Patroni dependencies
      ansible.builtin.apt:
        name:
          - "postgresql-{{ postgres_version }}"
          - "postgresql-client-{{ postgres_version }}"
          - python3-pip
          - python3-psycopg2
          - python3-venv
          - watchdog
        state: present
        update_cache: true

    - name: Stop and disable the distro postgresql unit (Patroni will manage PG)
      ansible.builtin.systemd:
        name: postgresql
        enabled: false
        state: stopped
      ignore_errors: true

    - name: Create Patroni virtualenv
      ansible.builtin.command:
        cmd: python3 -m venv /opt/patroni
        creates: /opt/patroni/bin/python

    - name: Install Patroni + etcd client in venv
      ansible.builtin.pip:
        name:
          - "patroni[etcd3]==3.3.0"
          - psycopg2-binary
        virtualenv: /opt/patroni

    - name: Create Patroni config directory
      ansible.builtin.file:
        path: /etc/patroni
        state: directory
        owner: postgres
        group: postgres
        mode: "0750"

    - name: Template patroni.yml
      ansible.builtin.template:
        src: patroni.yml.j2
        dest: /etc/patroni/patroni.yml
        owner: postgres
        group: postgres
        mode: "0640"
      notify: restart patroni

    - name: Template Patroni systemd unit
      ansible.builtin.copy:
        dest: /etc/systemd/system/patroni.service
        mode: "0644"
        content: |
          [Unit]
          Description=Patroni PostgreSQL HA
          After=network.target etcd.service
          Wants=network-online.target

          [Service]
          Type=simple
          User=postgres
          Group=postgres
          ExecStart=/opt/patroni/bin/patroni /etc/patroni/patroni.yml
          KillMode=process
          Restart=on-failure
          RestartSec=10
          TimeoutSec=30
          LimitNOFILE=65536

          [Install]
          WantedBy=multi-user.target
      notify:
        - reload systemd
        - restart patroni

    - name: Ensure Patroni data dir exists and is owned by postgres
      ansible.builtin.file:
        path: "{{ patroni_data_dir }}"
        state: directory
        owner: postgres
        group: postgres
        mode: "0700"

    - name: Enable and start Patroni
      ansible.builtin.systemd:
        name: patroni
        daemon_reload: true
        enabled: true
        state: started

  handlers:
    - name: reload systemd
      ansible.builtin.systemd:
        daemon_reload: true

    - name: restart patroni
      ansible.builtin.systemd:
        name: patroni
        state: restarted
```

```jinja
{# templates/patroni.yml.j2 #}
scope: {{ patroni_scope }}
namespace: /service/
name: {{ inventory_hostname }}

restapi:
  listen: 0.0.0.0:8008
  connect_address: {{ ansible_host }}:8008

etcd3:
  hosts: {{ etcd_endpoints }}

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    synchronous_mode: true
    synchronous_mode_strict: false
    synchronous_node_count: 1
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 1024MB
        synchronous_commit: remote_apply
        synchronous_standby_names: "{{ patroni_sync_standby_names }}"
        max_connections: 500
        shared_buffers: 8GB
        effective_cache_size: 24GB

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 10.10.0.0/16 scram-sha-256
    - host replication replicator 10.20.0.0/16 scram-sha-256
    - host all all 10.0.0.0/8 scram-sha-256

  users:
    admin:
      password: "{{ vault_pg_admin_password }}"
      options:
        - createrole
        - createdb
    replicator:
      password: "{{ vault_pg_replicator_password }}"
      options:
        - replication

postgresql:
  listen: 0.0.0.0:5432
  connect_address: {{ ansible_host }}:5432
  data_dir: {{ patroni_data_dir }}
  bin_dir: {{ patroni_bin_dir }}
  pgpass: /tmp/pgpass0
  authentication:
    replication:
      username: replicator
      password: "{{ vault_pg_replicator_password }}"
    superuser:
      username: postgres
      password: "{{ vault_pg_superuser_password }}"
  parameters:
    unix_socket_directories: "/var/run/postgresql"

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
```

Key points:
- **etcd DCS** spans both sites plus a tiebreaker (5 nodes: 2 Chicago + 2 Dallas + 1 arbiter) so the cluster survives any single-site loss without split-brain.
- **Patroni sync mode** with `synchronous_commit: remote_apply` and `synchronous_standby_names: pg-dal-01` gives zero data loss — a commit in Chicago is not acknowledged until Dallas has applied it. At 12ms RTT, write latency is ~24ms, acceptable for a regulated workload.
- **Replication slots** prevent WAL from being recycled before the standby catches up.
- **Handler** `restart patroni` fires on any config change.

### Part C — Architecture
**Answer:**
**Automated failover orchestration — sequence of events:**

**Failure detection (what constitutes "site down"):**
- Multiple independent monitors must agree before triggering failover:
  1. **External synthetic checks** from 3+ geographic locations (e.g., Pingdom, Catchpoint, or your own probes in a third region) hitting `https://app.example.com/health` every 10s. Require 3 consecutive failures from ≥2 locations.
  2. **Inter-site ICMP + TCP probe** from Dallas to Chicago on multiple paths (dark fiber + internet). Require loss of all paths for 60s.
  3. **Patroni etcd quorum loss** in Chicago (etcd nodes in Chicago unreachable from Dallas side of the etcd cluster).
  4. **Kubernetes API** in Chicago non-responsive for 60s.
  - AND gate: site is declared down only if (1 OR 2) AND (3 OR 4) are true. Anything less is a partial failure and should page a human, not auto-failover.
- A dedicated orchestrator (a small HA Go service, or Rundeck / StackStorm / Cadence workflow) owns the decision. It runs in a third location (cloud region or colo) so it is never partitioned with either site.

**Failover sequence (in order):**

1. **T+0s:** Orchestrator declares Chicago down. Post to incident channel, page SRE on-call, start failover runbook.

2. **T+5s:** **Fence Chicago.** Issue API calls to the site routers / firewalls to drop all external traffic toward Chicago (BGP withdraw, if possible). This prevents a zombie primary from accepting writes during the transition. If Chicago is genuinely dead, this is a no-op; if it is a network partition, this is the critical split-brain prevention step.

3. **T+10s:** **PostgreSQL promotion.** Orchestrator calls `patronictl -c /etc/patroni/patroni.yml failover --master pg-chi-01 --candidate pg-dal-01 --force`, or equivalently `curl -s -XPOST http://pg-dal-01:8008/failover -d '{"candidate":"pg-dal-01"}'`. Patroni (backed by etcd quorum in Dallas + arbiter) promotes `pg-dal-01`, updates the leader key in etcd, and the other Dallas node becomes the new sync standby. Takes ~30s.

4. **T+40s:** **Redis Sentinel failover.** Sentinels in Dallas have already voted (sentinel quorum 3-of-5) and promoted the Dallas Redis replica to primary as soon as Chicago sentinels became unreachable for `down-after-milliseconds`. Orchestrator verifies `SENTINEL get-master-addr-by-name mymaster` returns a Dallas IP.

5. **T+45s:** **RabbitMQ.** With quorum queues replicated across sites, the Dallas members form a new majority (as long as quorum queue replicas are placed so Dallas has ≥ (n/2)+1). Orchestrator verifies queue availability via management API. For any non-quorum (classic mirrored) queues, expect potential data loss — we accept this as a known limitation and alert.

6. **T+50s:** **MinIO.** Already active-active via site replication; Dallas writes continue unchanged. Orchestrator verifies `mc admin replicate status` and records the replication lag at the moment of failover for the post-mortem.

7. **T+60s:** **DNS / GSLB failover.** Update Route53 (or F5 BIG-IP DNS / NS1 / Infoblox) failover policy. Health check on Chicago ALB has already marked it unhealthy; failover record automatically serves the Dallas ALB. TTL is 30s, so clients reconverge within 30–60s. For clients caching longer, the API Gateway in Dallas returns 307 redirects to regional endpoints.

8. **T+90s:** **Kubernetes workload verification.** Argo CD/Flux in the Dallas cluster shows all applications Synced/Healthy (they were already running active-active). External ingress now points at the Dallas ingress.

9. **T+120s:** **Update OpenTofu state.** Trigger the pipeline variant `apply_failover` which runs `tofu apply -var="primary_site=dallas"` against the infrastructure repo. This updates Route53 primary, updates any alarms, IAM trust, and monitoring dashboards to reflect Dallas as the primary. Because the change is expressed as a variable, `plan` shows only the intentional changes; state is not rewritten manually. The pipeline requires the on-call engineer's approval click to run `apply`.

10. **T+180s:** **All-clear.** Orchestrator posts the sequence log to the incident channel. RTO achieved ≈ 3 min.

**Split-brain handling:**
- **Fencing (step 2)** is the primary prevention. If Chicago is partitioned but alive, BGP withdrawal makes it unreachable to clients.
- **etcd quorum (3-of-5)** ensures that Chicago alone cannot elect a Patroni leader; only Dallas (2) + arbiter (1) = 3 can. If Chicago also loses arbiter connectivity, Chicago has no quorum and Patroni demotes itself to read-only.
- **Redis sentinel quorum** similarly placed (e.g., 2 in Chicago, 2 in Dallas, 1 arbiter).
- **MinIO active-active** has eventual-consistency semantics; on reconciliation, MinIO's site replication resolves conflicts by last-writer-wins per object. Accept this and monitor.
- **Application-level idempotency keys** on all writes so retries during partition do not double-process.
- **If** both sides end up promoted despite all of the above, the recovery procedure treats Dallas as authoritative, Chicago's diverged writes are exported via logical dump, human-reviewed, and replayed where appropriate.

**Failback to Chicago once it recovers:**
1. Re-establish network connectivity and validate inter-site links.
2. Rebuild Chicago Patroni nodes from the current Dallas primary: `pg_basebackup` (or `patronictl reinit pg-chi-01`) — this wipes their local state and streams fresh from Dallas.
3. Let them catch up as async replicas first, then promote one to sync replica once lag is zero.
4. Verify Redis replication, rebuild RabbitMQ quorum members in Chicago via `rabbitmqctl add_member`.
5. Let MinIO site replication catch up; monitor `minio_cluster_replication_last_hour_failed_count`.
6. Once Chicago is fully healthy and lag = 0 for ≥ 10 min, schedule a **planned** failback during a maintenance window: `patronictl switchover --master pg-dal-01 --candidate pg-chi-01`. Update Route53 primary. Run `tofu apply -var="primary_site=chicago"`.
7. Post-mortem: review detection time, fencing effectiveness, data loss (if any), and update runbook.

**Critical:** failback is always a planned operation, never automatic. Auto-failback invites flapping in partial-failure scenarios.
