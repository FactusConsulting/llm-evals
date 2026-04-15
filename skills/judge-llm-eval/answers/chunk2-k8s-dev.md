# Kubernetes + Development Knowledge Test Suite — Answers

---

## Section 1: Kubernetes (K1–K20)

### K1 — Easy
**Answer:**
A Deployment manages stateless, interchangeable replica pods: pods get random names, any pod can replace any other, and scaling/rolling updates happen in arbitrary order. A StatefulSet manages stateful workloads where pod identity matters: pods get stable, ordinal names (`web-0`, `web-1`, ...), stable network identities via a headless Service, stable per-pod PersistentVolumeClaims via `volumeClaimTemplates`, and ordered (sequential) creation, update, and termination. Use Deployment for web servers/APIs; use StatefulSet for databases, Kafka, Zookeeper, or anything that needs stable identity and storage.

### K2 — Easy
**Answer:**
A ClusterIP Service is assigned a stable virtual IP from the service CIDR. kube-proxy on each node watches the API for Services and their Endpoints (or EndpointSlices — the pods matching the Service's label selector) and programs the node's packet path (iptables, ipvs, or nftables) so that traffic destined for the ClusterIP is DNAT'd to one of the healthy backend pod IPs, load-balanced (round-robin by default). DNS (CoreDNS) resolves `<svc>.<ns>.svc.cluster.local` to the ClusterIP. The ClusterIP is only reachable from inside the cluster.

### K3 — Medium
**Answer:**
- **PersistentVolume (PV):** A cluster-scoped resource representing an actual piece of storage (NFS share, EBS volume, Ceph RBD, local disk, etc.), provisioned either statically by an admin or dynamically by a StorageClass. It describes capacity, access modes, reclaim policy, and the backend driver.
- **PersistentVolumeClaim (PVC):** A namespaced request for storage by a user/pod — "I need 10Gi ReadWriteOnce". The pod mounts the PVC, not the PV directly.
- **StorageClass (SC):** A cluster-scoped template that describes a class of storage and, crucially, names a CSI/in-tree provisioner plus parameters (disk type, IOPS, zone, etc.).

Relation: A PVC references (explicitly or via default) a StorageClass. The control plane's PV controller uses the SC's provisioner to dynamically create a matching PV and binds PVC↔PV 1:1. The pod references the PVC in `volumes[].persistentVolumeClaim.claimName`. On deletion, the PV's `reclaimPolicy` (Delete/Retain) decides the fate of the underlying storage.

### K4 — Medium
**Answer:**
1. `kubectl describe pod <name>` — read the Events at the bottom for scheduler, kubelet, image-pull, and probe messages; check restart count and last state.
2. `kubectl logs <name> --previous` — the previous container instance's stdout/stderr is where the actual crash reason lives (current logs are from the new attempt).
3. Check image and command: wrong `image:` tag, missing binary, wrong `command`/`args`, or entrypoint exiting 0/non-zero immediately. Shell in with `kubectl debug` or an ephemeral container if the image has no shell.
4. Check configuration: missing/invalid ConfigMap, Secret, or env var; missing volume mount; wrong file permissions (runAsUser/fsGroup); DB or dependency unreachable.
5. Check probes: an overly aggressive livenessProbe killing the container before it's ready; too-short `initialDelaySeconds`.
6. Check resources: OOMKilled (exit 137) in `lastState.terminated.reason` means bump `limits.memory`; CPU throttling can also cause probe failures.
7. Check node: `kubectl get events -n <ns>`, node conditions, disk/inode pressure, image pull errors from a broken registry/credential.

### K5 — Medium
**Answer:**
CoreDNS is the in-cluster DNS server (a Deployment in `kube-system` fronted by a Service, usually named `kube-dns`, with ClusterIP `10.96.0.10` by default). Every pod's `/etc/resolv.conf` points at that ClusterIP (via kubelet's `--cluster-dns`). CoreDNS resolves:
- `*.svc.cluster.local` → Service ClusterIPs (and headless Services → pod IPs).
- Pod DNS names under `*.pod.cluster.local`.
- External names via upstream forwarders defined in the Corefile (`forward . /etc/resolv.conf` typically).

If all CoreDNS pods are down, in-cluster DNS resolution fails: new connections that rely on name lookups (to Services or external hostnames) break. Already-established TCP connections keep working because they have resolved IPs. Pods themselves keep running; kube-proxy and direct IP traffic still work. Kubelet's `nodelocaldns` cache (if deployed) can mitigate short CoreDNS outages.

### K6 — Hard
**Answer:**
The scheduler (kube-scheduler) runs a two-phase pipeline for each unscheduled pod:

1. **Filtering (predicates / Filter plugins):** Eliminate nodes that cannot run the pod. Plugins include:
   - `NodeResourcesFit` — node has enough allocatable CPU/memory/ephemeral-storage/extended resources to satisfy the pod's `requests`.
   - `NodeAffinity` / `NodeSelector` — node labels match `nodeSelector`/`nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution`.
   - `TaintToleration` — pod tolerates all `NoSchedule`/`NoExecute` taints on the node.
   - `PodTopologySpread`, `InterPodAffinity` — spread/affinity constraints feasible.
   - `VolumeBinding`, `VolumeZone`, `NodeVolumeLimits` — PVCs can bind and the node is in the right zone and under attach limits.
   - `NodePorts` — requested host ports free.
   - `NodeUnschedulable`, `NodeName` — node is schedulable and (if set) matches `.spec.nodeName`.

2. **Scoring (priorities / Score plugins):** Rank feasible nodes 0–100. Plugins include `NodeResourcesFit` (LeastAllocated/MostAllocated), `InterPodAffinity`, `PodTopologySpread`, `ImageLocality` (prefers nodes that already have the image), `TaintToleration`, and `NodeAffinity` (preferred). Scores are weighted and summed; the highest-scoring node wins (ties broken randomly).

After scoring, the scheduler writes `.spec.nodeName` via a `Bind` call; kubelet on that node takes over and starts the pod. Preemption runs if no node fits and the pod has a high `priorityClass` — lower-priority pods get evicted to make room.

### K7 — Hard
**Answer:**
Scheduling is based on **requests**, not limits. The node has 4 GiB allocatable, 3.5 GiB already requested, leaving 500 MiB. The pod requests 256 MiB, which fits, so the scheduler places it on the node (assuming no other filter fails).

At runtime the pod uses 600 MiB, which exceeds its 512 MiB memory limit. Memory limits are enforced by the kernel cgroup. Memory is incompressible, so the kernel OOM-killer kills the container with exit code 137 and kubelet records `State.Terminated.Reason: OOMKilled`. The pod's `restartPolicy` (default `Always` for Deployment-managed pods) then restarts the container; repeated kills drive it into `CrashLoopBackOff`. Note the node itself is fine — only the offending container is killed, because the cgroup limit scopes the OOM to that container.

### K8 — Hard
**Answer:**
1. **DNS / external LB:** Client resolves the hostname to the public IP of an external load balancer (cloud LB from a `LoadBalancer` Service fronting the ingress controller, or a DNS record pointing at a node IP / MetalLB VIP).
2. **External LB → node:** LB forwards TCP 80/443 to one of the nodes running an ingress-controller pod (via a NodePort or hostPort).
3. **kube-proxy / iptables on the node:** If it's a NodePort, iptables (or IPVS) DNATs the packet from `NODE_IP:NODEPORT` to the ingress controller pod IP on the overlay network (picking one backend from the EndpointSlice).
4. **CNI network:** The packet traverses the pod network (e.g., Cilium, Calico, Flannel) to the ingress controller pod.
5. **NGINX ingress controller:** Terminates TLS (using the Secret referenced by `tls.secretName`), parses `Host:` + path, and matches an `Ingress` rule. The controller has watched the API server and rebuilt its `nginx.conf` (or uses the Lua dynamic upstream) so that each ingress rule maps to an `upstream` block whose servers are the **pod IPs of the backend Service's EndpointSlice** — it bypasses the Service ClusterIP to do its own load balancing and keep-alives.
6. **Upstream selection:** NGINX picks a backend pod IP (round-robin / ewma) and opens a connection directly to `POD_IP:containerPort`.
7. **CNI to backend pod:** Packet is routed across the pod network to the destination node and delivered to the application container's listening socket.
8. **Response:** Flows back through the same path; TLS re-encryption if needed; LB returns bytes to the client.

`Service` + `Endpoints`/`EndpointSlice` are still critical — the ingress controller reads them to know which pod IPs to proxy to — but the actual data path skips the Service ClusterIP and `kube-proxy` DNAT.

### K9 — Medium
**Answer:**
A `NetworkPolicy` is a namespaced resource, enforced by the CNI plugin (Calico, Cilium, etc. — not kube-proxy), that restricts ingress and/or egress traffic to pods matching a `podSelector`.

Default behavior: **if no NetworkPolicy selects a pod, all traffic to and from that pod is allowed** (pods are "non-isolated"). Kubernetes networking is allow-all by default.

As soon as at least one NetworkPolicy selects a pod for a given direction (`policyTypes: [Ingress]` and/or `[Egress]`), that pod becomes **isolated for that direction**: only traffic explicitly permitted by the union of all policies selecting it is allowed; everything else is dropped. Policies are additive — there is no explicit `deny`, you achieve deny by isolating the pod and only allowing what you want. A typical "default deny ingress" policy selects all pods (`podSelector: {}`) with empty `ingress: []`.

### K10 — Medium
**Answer:**
- **RollingUpdate (default):** New ReplicaSet is scaled up and old ReplicaSet is scaled down gradually, bounded by `maxSurge` (extra pods above desired) and `maxUnavailable` (how many can be down). Zero-downtime if the app supports it; old and new versions run simultaneously.
- **Recreate:** The old ReplicaSet is fully scaled to 0, then the new ReplicaSet is scaled up. Causes downtime; no two versions coexist.

Choose `Recreate` when:
- The app cannot tolerate two versions running at once (e.g., a schema migration that is not backward-compatible, or a singleton writer).
- You're using a `ReadWriteOnce` PVC that can only be mounted by one pod at a time.
- Downtime during deploys is acceptable and you want the simplest "stop, start" semantics.

### K11 — Easy
**Answer:**
A namespace is a virtual cluster scope that groups and isolates resources (Pods, Services, ConfigMaps, Secrets, RBAC bindings, quotas). It provides a naming scope (two Deployments named `api` can coexist in different namespaces) and a boundary for RBAC, ResourceQuotas, LimitRanges, and NetworkPolicies. Note: namespaces do not isolate network traffic by default — that requires NetworkPolicies.

Default namespaces in a new cluster:
- `default` — where resources without an explicit namespace land.
- `kube-system` — control-plane and add-on components (CoreDNS, kube-proxy, etc.).
- `kube-public` — world-readable, used for cluster-info.
- `kube-node-lease` — node heartbeat Lease objects.

### K12 — Easy
**Answer:**
`kubectl describe pod <name>` prints a human-readable dump of the pod object plus related events. Unlike `kubectl get pod` (which shows name, ready, status, restarts, age), `describe` additionally shows:
1. The full Events timeline (scheduling, image pull, container start, probe failures, OOMKills).
2. Container details: image, image ID, command/args, ports, environment variables, mounted volumes, resource requests/limits.
3. Current and last termination state (reason, exit code, signal, started/finished timestamps, restart count).
4. Readiness/liveness/startup probe definitions and their current status.
5. Node it's scheduled on, pod IP, QoS class, priority, tolerations, and node selectors.
6. Volumes and the Secrets/ConfigMaps/PVCs they resolve to.

### K13 — Easy
**Answer:**
A ConfigMap is a namespaced API object storing non-sensitive key/value configuration data (strings or binary). A pod can consume it in several ways:

1. **Environment variables:** `envFrom.configMapRef` (import all keys) or `env[].valueFrom.configMapKeyRef` (one key).
2. **Volume mount:** `volumes[].configMap.name` mounted into a path — each key becomes a file whose content is the value. Supports `items` to project specific keys, `defaultMode` for permissions, and automatic updates when the ConfigMap changes (subPath mounts do not auto-update).
3. **Command-line arguments:** via the env-var form above, then referenced in `args` with `$(VAR_NAME)`.
4. **By the kubelet itself:** e.g. the `--pod-manifest-path` static config is not a ConfigMap, but controllers like the kubelet config and kube-proxy consume ConfigMaps directly.

### K14 — Easy
**Answer:**
- **ClusterIP (default):** Allocates a virtual IP reachable only inside the cluster. Used for internal service-to-service communication.
- **NodePort:** Superset of ClusterIP. Additionally opens the same TCP/UDP port (30000–32767 by default) on every node; external traffic to `NODE_IP:NODEPORT` is forwarded by kube-proxy to the Service's ClusterIP and then to a pod.
- **LoadBalancer:** Superset of NodePort. Additionally tells the cloud provider's controller to provision an external load balancer (ELB, GCP LB, Azure LB, MetalLB, etc.) that targets the NodePort on the nodes and exposes a public IP/hostname in `.status.loadBalancer.ingress`.

### K15 — Easy
**Answer:**
A DaemonSet ensures that **one copy of a pod runs on every node** (or every node matching a `nodeSelector`/affinity). New nodes automatically get the pod; removed nodes have it cleaned up. Use it for node-level agents: log shippers (Fluent Bit, Promtail, Alloy), node-exporter, CNI plugins, kube-proxy, CSI node plugins, security agents (Falco). Choose a DaemonSet over a Deployment when the workload is tied to the node itself (needs access to host networking, `/var/log`, `/var/run/docker.sock`, or must be co-located 1:1 with each node), rather than being a scalable application.

### K16 — Medium
**Answer:**
- **Taints** are set on nodes (`kubectl taint nodes <n> key=value:NoSchedule|PreferNoSchedule|NoExecute`) and **repel** pods: only pods with a matching **toleration** can be scheduled (`NoSchedule`), preferred away (`PreferNoSchedule`), or are evicted if already running (`NoExecute`).
- **Node affinity** is set on the **pod** and **attracts** pods to nodes whose labels match, via `requiredDuringSchedulingIgnoredDuringExecution` (hard) or `preferredDuringSchedulingIgnoredDuringExecution` (soft).

Key difference: taints are a **node-driven opt-out** ("keep everyone off me unless they tolerate"), node affinity is a **pod-driven opt-in** ("I want to land on nodes like this"). They're complementary and are typically combined for dedicated nodes.

Practical use cases:
- Taints/tolerations: dedicate GPU nodes with `nvidia.com/gpu=true:NoSchedule` so only GPU workloads land there; mark nodes under maintenance with `NoExecute` to drain them.
- Node affinity: pin a latency-sensitive workload to nodes labeled `topology.kubernetes.io/zone=eu-west-1a` or `node-type=memory-optimized`.

### K17 — Medium
**Answer:**
A Kubernetes **Operator** is a custom controller plus one or more CustomResourceDefinitions (CRDs) that encodes **domain-specific operational knowledge** for a stateful or complex application (databases, message queues, etc.). Users declare desired state via a custom resource (e.g., `kind: PostgresCluster`) and the operator's reconcile loop drives the cluster toward that state — handling provisioning, backups, failover, version upgrades, scaling, and repair automatically.

A **standard controller** reconciles built-in resources (Deployment → ReplicaSets → Pods) and only knows about generic primitives. An **operator** is still a controller, but it:
- Extends the API with CRDs so the app's domain concepts become first-class Kubernetes objects.
- Bundles runbook-style operational logic ("Day 2 ops") into code — e.g. pausing writes, taking a consistent snapshot, rolling a primary.

Problems solved: encoding human SRE knowledge as software, declarative lifecycle management of stateful apps, consistent multi-tenant operation, version/upgrade automation, and self-healing beyond what generic Deployment/StatefulSet offer. Built using the Operator SDK, Kubebuilder, or controller-runtime. Examples: prometheus-operator, cert-manager, etcd-operator, CloudNativePG, Strimzi (Kafka).

### K18 — Hard
**Answer:**
etcd uses the **Raft** consensus algorithm and provides **strong (linearizable) consistency** for reads and writes by default. Every write must be committed to a majority (quorum) of the etcd members (⌈N/2⌉+1): 2 of 3, 3 of 5. Linearizable reads also go through the leader. `kube-apiserver` fronts etcd and offers two read modes: default strong (`ResourceVersion=""`) and cache/quorum-bypassing (`ResourceVersion="0"`, eventually consistent).

**Losing quorum:** If fewer than ⌈N/2⌉+1 members are alive, etcd cannot elect a leader or accept writes. The cluster becomes **read-only from cache** at best: `kube-apiserver` serves stale data from its watch cache, but no new writes, pod scheduling, lease renewals, or controller reconciliations succeed. Existing pods keep running (kubelet works off its local cache), but the control plane is effectively frozen. Node leases eventually expire and the cluster looks degraded.

**Recovery from losing 2 of 3 etcd members permanently:**
1. Stop the remaining etcd member.
2. On the surviving node, take an etcd snapshot (or use the existing data dir) and restore it with `etcdctl snapshot restore <snap> --name <m1> --initial-cluster m1=https://... --initial-cluster-token <new> --initial-advertise-peer-urls https://...` — this creates a **new** single-member cluster from the snapshot (etcd requires `--force-new-cluster` conceptually via the restore).
3. Start etcd with the restored data-dir. You now have a healthy 1-member cluster.
4. Add two fresh members with `etcdctl member add` and bring them online with matching `--initial-cluster-state=existing`, restoring the 3-member quorum.
5. Verify with `etcdctl endpoint health` and `member list`, then confirm `kube-apiserver` is healthy.

Always keep regular etcd snapshots (`etcdctl snapshot save`) — they're the authoritative recovery artifact.

### K19 — Hard
**Answer:**
Kubernetes RBAC authorizes API requests by matching a (subject, verb, resource) tuple against Roles.

- **Role:** Namespaced. Grants verbs (`get`, `list`, `watch`, `create`, `update`, `patch`, `delete`, `deletecollection`) on resources within a single namespace.
- **ClusterRole:** Cluster-scoped. Same shape as Role but applies cluster-wide, and is also the only way to grant permissions on cluster-scoped resources (nodes, PVs, namespaces themselves) or non-resource URLs (`/healthz`).
- **RoleBinding:** Namespaced. Binds a set of subjects (Users, Groups, ServiceAccounts) to a Role **or** a ClusterRole (in which case the ClusterRole's rules apply only within the binding's namespace — a common pattern for reusable role templates).
- **ClusterRoleBinding:** Cluster-scoped. Binds subjects to a ClusterRole cluster-wide.

**Manifests — read-only access to pods and pod logs in namespace `dev` for user `alice`:**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev
  name: pod-and-log-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: dev
  name: alice-pod-and-log-reader
subjects:
  - kind: User
    name: alice
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-and-log-reader
  apiGroup: rbac.authorization.k8s.io
```

### K20 — Hard
**Answer:**
Inside a pod, kubelet writes `/etc/resolv.conf` with a search list and `options ndots:5` (default). Example:

```
search myns.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

The `ndots:N` option tells the resolver: "if the queried name contains **fewer than N dots**, try it as a **relative** name against each search-domain entry **first**, and only fall back to treating it as absolute if none match". With `ndots:5`, a name like `api.github.com` has 2 dots (<5) so the resolver first tries `api.github.com.myns.svc.cluster.local`, `api.github.com.svc.cluster.local`, `api.github.com.cluster.local`, each returning NXDOMAIN, and only then `api.github.com` — each attempt doubled for A + AAAA — yielding 8+ DNS queries per lookup. Under CoreDNS load or transient packet loss, retries stack up and each external lookup can exceed 5 seconds.

**Fixes:**
1. **Fully qualify names** — append a trailing dot (`api.github.com.`) so the resolver treats them as absolute and skips the search list.
2. **Lower ndots** via `dnsConfig` on the pod:

```yaml
spec:
  dnsPolicy: ClusterFirst
  dnsConfig:
    options:
      - name: ndots
        value: "1"
      - name: single-request-reopen
  # Optionally restrict search domains to just what you need:
    searches:
      - myns.svc.cluster.local
```

3. Deploy **NodeLocal DNSCache** to move resolution to a per-node cache, reducing latency and retry cost.
4. On kernels where it helps, add `single-request` or `single-request-reopen` to serialize A/AAAA and avoid the glibc port-reuse conntrack race.

---

## Section 2: Docker/Development (D1–D20)

### D1 — Easy
**Answer:**
- **`git merge`** integrates one branch into another by creating a **merge commit** with two parents, preserving the exact history of both branches. Non-destructive; safe on shared branches.
- **`git rebase`** replays the commits of your branch on top of another base, producing a **linear history** with new commit hashes. It rewrites history.

Avoid rebasing commits that have already been **pushed and shared** with other collaborators — rewriting shared history forces everyone else to reset their branches and causes merge headaches. Rule of thumb: rebase local, private work; merge public, shared branches. Also avoid rebasing when preserving the exact merge topology matters (e.g., audit requirements).

### D2 — Easy
**Answer:**
- **TCP (Transmission Control Protocol):** connection-oriented, reliable, ordered, byte-stream; uses a 3-way handshake (SYN/SYN-ACK/ACK), acknowledgements, retransmission, flow control, and congestion control. Higher overhead, higher latency. Used by HTTP/1.1, HTTPS, SSH, SMTP, FTP.
- **UDP (User Datagram Protocol):** connectionless, unreliable, unordered datagrams; no handshake, no retransmission, no congestion control. Minimal overhead, low latency. Used by DNS, DHCP, NTP, QUIC (HTTP/3), VoIP/RTP, most video streaming.

### D3 — Medium
**Answer:**
A **race condition** occurs when the correctness of a program depends on the non-deterministic ordering or interleaving of concurrent operations on shared state. Two threads reading, modifying, and writing the same variable without synchronization can lose updates.

Concrete example in Go:

```go
var counter int
var wg sync.WaitGroup
for i := 0; i < 1000; i++ {
    wg.Add(1)
    go func() {
        defer wg.Done()
        counter++ // read-modify-write, not atomic
    }()
}
wg.Wait()
fmt.Println(counter) // often < 1000
```

`counter++` compiles to load → add → store. Two goroutines can load the same value, each increment to N+1, and both store N+1, losing one increment. Fix with a `sync.Mutex`, `atomic.AddInt64`, or a channel — anything that serializes access. (Run with `go run -race` to detect.)

### D4 — Medium
**Answer:**
- **Symmetric encryption:** same shared secret key encrypts and decrypts (AES, ChaCha20). Very fast, suitable for bulk data, but requires a secure way to share the key.
- **Asymmetric (public-key) encryption:** a keypair where the public key encrypts and only the matching private key decrypts (RSA, ECDH/ECDSA, Ed25519). Solves key distribution but is orders of magnitude slower.

**TLS combines both:**
1. Handshake uses **asymmetric** cryptography: the server presents an X.509 certificate containing its public key, signed by a CA. The client verifies the chain. The client and server then perform a key-exchange (ECDHE) to derive a shared secret without ever sending it on the wire — the asymmetric keys authenticate the exchange and (historically) encrypted the pre-master secret.
2. Once both sides have derived matching symmetric session keys, the bulk record layer uses **symmetric** encryption (AES-GCM or ChaCha20-Poly1305) for the actual application data — fast and cheap.

So: asymmetric for authentication + key agreement, symmetric for bulk data.

### D5 — Medium
**Answer:**
A Docker image is built as an ordered stack of **read-only layers**, one per image-building instruction (`FROM`, `RUN`, `COPY`, `ADD`). Each layer is a filesystem diff; containers add a thin read-write layer on top via an overlay filesystem (overlay2). Layers are content-addressed and shared between images.

Docker's build cache reuses a layer when the instruction and its inputs (file contents for `COPY`, the literal command for `RUN`, etc.) are identical to a previous build. If any layer's inputs change, that layer **and every layer after it** is invalidated and rebuilt.

**Dockerfile best practices that fall out of this:**
- Order instructions from **least to most frequently changing** so expensive layers (apt-get, package installs) stay cached.
- Copy dependency manifests (`package.json`, `go.mod`, `requirements.txt`) and install deps **before** copying your source, so source changes don't invalidate the dependency layer.
- Combine related `RUN` commands in one layer (`&&`) and clean up in the same layer (`rm -rf /var/lib/apt/lists/*`) so cleanup actually shrinks the image.
- Use `.dockerignore` to keep unrelated files out of the build context so they don't bust the cache.
- Use multi-stage builds to discard toolchains from the final image.
- Pin base images by digest for deterministic caching.

### D6 — Medium
**Answer:**
1. **Reproduce + scope:** Is every call 503, or only some? From one client or many? Which endpoint(s)? Add a request ID and curl the endpoint directly to bypass the SDK.
2. **Logs on the server:** application logs, access logs, and load-balancer/ingress logs for the failing requests — 503 from an ingress/LB often means "no healthy upstream", from the app often means "overloaded / shedding".
3. **Health and readiness:** are some backend instances failing readiness probes? `kubectl get pods`, `get endpoints`, ALB target health.
4. **Resource + saturation (USE method):** CPU, memory, file descriptors, DB connection pool, thread pool, event loop lag — 503 often correlates with a saturated pool timing out.
5. **Dependencies:** DB, cache, downstream APIs. Check their latency and error rates; circuit breakers tripping produce 503.
6. **Recent changes:** last deploy, config change, feature flag, traffic spike, cron job? Correlate the start of the 503s on a dashboard.
7. **Network path:** DNS, TLS handshake failures, keepalive timeouts, MTU/PMTUD, connection resets at the LB. `kubectl exec` + `curl -v` from inside the cluster vs. from outside.
8. **Rate limits / auth:** some gateways return 503 on throttling; check rate-limit metrics and WAF rules.

Order: start with logs + scope (cheap, narrows the space), then saturation and dependencies (most common cause), then recent changes, then network.

### D7 — Hard
**Answer:**
The **CAP theorem** (Brewer) states that a distributed data store can provide at most **two** of the following three guarantees in the face of a network partition:
- **Consistency (C):** every read sees the most recent successful write (linearizability).
- **Availability (A):** every request receives a non-error response (not necessarily the latest data).
- **Partition tolerance (P):** the system keeps operating despite arbitrary packet loss/delays between nodes.

Since partitions are unavoidable in real networks, the real choice during a partition is **CP vs. AP**.

- **CP example — etcd / ZooKeeper / Google Spanner / HBase:** during a partition, the minority side refuses writes (and often reads) to preserve consistency. etcd uses Raft: no quorum → no progress. You lose availability on the minority partition but never see stale or divergent data. This is why etcd backs Kubernetes — the control plane needs a single source of truth.
- **AP example — Cassandra / DynamoDB (tunable) / Riak / DNS:** during a partition, every node keeps accepting reads and writes. Replicas may diverge; conflicts are reconciled later (last-write-wins, vector clocks, CRDTs, read-repair). You get continuous availability at the cost of potentially stale or conflicting reads. Suitable for shopping carts, social feeds, metrics ingestion.

Modern systems are usually tunable: Cassandra and Dynamo let you pick per-request consistency levels; Spanner leans CP but uses TrueTime to minimize availability loss.

### D8 — Medium
**Answer:**
- **Vertical scaling (scale up):** give a single machine more resources — bigger CPU, more RAM, faster disk. Simple, no code changes, but bounded by hardware limits, expensive per unit capacity, and the single machine remains a single point of failure.
- **Horizontal scaling (scale out):** add more machines/instances and distribute load across them. Effectively unlimited ceiling, better fault tolerance, but requires the architecture to support it.

**Architectural patterns that enable horizontal scaling:**
- **Stateless services:** move session/state out of the process (into Redis, a DB, or JWTs) so any instance can handle any request; put a load balancer in front.
- **Sharding / partitioning:** split data by key range or hash across nodes (Cassandra, MongoDB, Kafka partitions).
- **Replication + read replicas:** scale read traffic by fanning out to replicas.
- **Message queues / event-driven architecture:** decouple producers from consumers so you can scale workers independently (Kafka, RabbitMQ, SQS).
- **Caching tiers:** Redis/Memcached/CDN offload hot reads from the backend.
- **CQRS / microservices:** isolate bounded contexts so each can scale on its own resource profile.
- **Consistent hashing / distributed hash tables:** allow adding/removing nodes without massive rebalancing.

### D9 — Easy
**Answer:**
An environment variable is a named string held in a process's environment block, inherited by child processes. Programs read them (e.g., `PATH`, `HOME`, `LANG`) to discover configuration without hard-coding it.

Set one for the current shell: `export FOO=bar`.

To persist across **shell sessions** on Linux, append the export to a shell startup file:
- Bash interactive login: `~/.bash_profile` or `~/.profile`.
- Bash interactive non-login (most terminal emulators): `~/.bashrc`.
- Zsh: `~/.zshrc` (or `~/.zshenv` for every zsh invocation).
- System-wide: `/etc/environment` (simple `KEY=value`, no `export`) or a file in `/etc/profile.d/`.

For graphical sessions / systemd user services, `~/.config/environment.d/*.conf` or `systemctl --user set-environment` may also be needed.

### D10 — Easy
**Answer:**
**JSON (JavaScript Object Notation)** is a lightweight data-interchange format with a strict grammar: objects (`{}`), arrays (`[]`), strings, numbers, booleans, and `null`. No comments, no trailing commas, keys must be double-quoted strings.

**YAML (YAML Ain't Markup Language)** is a human-friendly superset (in practice) of JSON that uses indentation for structure, supports comments (`#`), multi-line strings, anchors/aliases (`&a`, `*a`), and multiple documents per file (`---`).

**Advantages:**
- JSON: unambiguous, machine-parseable grammar; native in JavaScript; ubiquitous in HTTP APIs; fast to parse.
- YAML: much more readable for humans, supports comments, better for configuration files and Kubernetes/Ansible/CI manifests.

### D11 — Easy
**Answer:**
A **REST (Representational State Transfer) API** exposes resources over HTTP using URLs (`/users/123`) and standard HTTP verbs, typically exchanging JSON. It's stateless (each request carries all needed context) and follows conventions around resource naming, status codes, and HATEOAS (optional).

- **GET** — retrieve a resource. Safe (no side effects) and idempotent.
- **POST** — create a new resource (or invoke a non-idempotent action). Not idempotent: repeating may create duplicates.
- **PUT** — replace/upsert a resource at a known URL with the full representation. Idempotent.
- **DELETE** — remove the resource. Idempotent.

(PATCH exists for partial updates.)

### D12 — Easy
**Answer:**
**Version pinning** means specifying exact versions of your dependencies (and ideally of transitive dependencies via a lockfile) rather than relying on ranges like `^1.2.0` or `latest`. Examples: `requests==2.31.0` in `requirements.txt`, `package-lock.json` / `yarn.lock`, `go.sum`, `Gemfile.lock`, `Cargo.lock`, image digests (`@sha256:...`) in Dockerfiles.

It matters for **reproducible builds** because without pinning, two builds of the same commit — performed on different days or machines — can resolve to different versions, producing different artifacts, introducing surprise breakage, security regressions, or bugs that can't be bisected. Pinning guarantees bit-for-bit (or at least semantically) identical dependency closures, making builds deterministic, debuggable, auditable, and safe to re-run for security patches or rollbacks.

### D13 — Easy
**Answer:**
- **Compiled language:** source code is translated ahead-of-time into machine code (or another low-level form) by a compiler; the resulting binary runs directly on the CPU. Generally faster at runtime, catches more errors at build time, but build step required. Examples: **C, C++, Rust, Go**.
- **Interpreted language:** source code is executed directly by an interpreter at runtime, one statement at a time, without a prior native-code build. Faster iteration, more dynamic, but slower execution. Examples: **Python, Ruby, JavaScript (in the browser historically), Bash**.

The line is blurry: Java and C# compile to bytecode executed by a VM with JIT; modern JavaScript engines (V8) JIT-compile; Python compiles to `.pyc` bytecode. The key distinction is whether translation to machine code happens ahead of time or at runtime.

### D14 — Medium
**Answer:**
A **reverse proxy** sits in front of one or more backend servers and receives client requests on their behalf, then forwards them to the appropriate backend. Clients talk to the proxy as if it were the origin and usually don't know backends exist. A **forward proxy** sits in front of clients and forwards their outgoing requests to arbitrary servers on the internet; the proxy represents the client side.

Reverse proxy responsibilities: TLS termination, load balancing, caching, compression, request routing based on Host/path, authentication, rate limiting, WAF, centralized logging, hiding backend topology. Forward proxy responsibilities: egress control, content filtering, caching for a set of clients, anonymity (Tor), corporate internet access policy.

**Common reverse proxy servers:**
- **NGINX** — high-performance HTTP(S) reverse proxy / load balancer; common as a Kubernetes ingress controller terminating TLS and routing to Services.
- **HAProxy** — battle-tested TCP/HTTP load balancer; great for high-throughput L4/L7 load balancing in front of stateful services like databases or SMTP.
- (Also: Envoy, Traefik, Caddy, AWS ALB, Cloudflare.)

### D15 — Medium
**Answer:**
A **deadlock** is a state in which a set of processes/threads are each blocked waiting for a resource held by another in the set, so none can make progress.

The four **Coffman conditions**, all of which must hold simultaneously:
1. **Mutual exclusion** — at least one resource must be held in a non-shareable mode (only one holder at a time).
2. **Hold and wait** — a process holding at least one resource is waiting to acquire additional resources that are currently held by other processes.
3. **No preemption** — resources cannot be forcibly taken from the processes holding them; they must be released voluntarily.
4. **Circular wait** — there exists a set of processes {P1, P2, ..., Pn} such that P1 waits for a resource held by P2, P2 waits for P3, ..., Pn waits for P1.

Break any one condition to prevent deadlock: enforce a global lock ordering (breaks circular wait), use try-lock with back-off (breaks hold-and-wait / no-preemption), or reduce shared mutability.

### D16 — Hard
**Answer:**
**Eventual consistency** is a liveness guarantee: if no new writes are made to a given item, **eventually** all replicas will converge on the same value. It says nothing about how long "eventually" is; in between, reads may be stale or divergent.

**Cassandra** is eventually consistent with **tunable consistency** — every read and write specifies a consistency level that controls how many replicas must acknowledge the operation before it's considered successful. Core levels (assuming replication factor RF):
- `ONE`, `TWO`, `THREE` — N replicas must respond.
- `QUORUM` — ⌈RF/2⌉+1 replicas.
- `LOCAL_QUORUM` — quorum within the local datacenter.
- `EACH_QUORUM` — quorum in every datacenter.
- `ALL` — every replica.
- `ANY` (writes only) — at least one node, possibly a hinted handoff coordinator.
- `LOCAL_ONE`, `SERIAL` / `LOCAL_SERIAL` (for lightweight transactions / Paxos).

**Read-after-write (strong) consistency** in Cassandra is achieved when `R + W > RF` — the read and write quorums overlap by at least one replica, so any read is guaranteed to see at least one node that has the latest write. The canonical recipe is `QUORUM` reads + `QUORUM` writes (R=W=⌈RF/2⌉+1 → R+W > RF). In multi-DC, use `LOCAL_QUORUM` for both.

Additionally, Cassandra uses **read repair** (sync/async), **hinted handoff** (buffered writes for down nodes), and periodic **anti-entropy repair** (`nodetool repair`, Merkle trees) to converge replicas over time. For true linearizable operations (compare-and-set), Cassandra offers **lightweight transactions** using Paxos (`SERIAL`/`LOCAL_SERIAL` consistency), at a significant performance cost.

### D17 — Hard
**Answer:**
**mTLS (mutual TLS)** is TLS where **both** sides present and verify X.509 certificates, so the server authenticates the client **and** the client authenticates the server. Standard TLS only authenticates the server.

**Handshake (TLS 1.3, simplified):**
1. **ClientHello:** client sends supported TLS versions, cipher suites, a random nonce, its key-share (ECDHE public keys), SNI, and extensions.
2. **ServerHello:** server picks the version and cipher, sends its random nonce and its key-share. Both sides now derive the handshake traffic secret via ECDHE; subsequent handshake messages are encrypted.
3. **Server `Certificate`:** server sends its X.509 certificate chain.
4. **Server `CertificateVerify`:** server signs a transcript hash with its certificate's private key — proves it **owns** the private key matching the cert.
5. **Server `CertificateRequest`:** server asks the client for a cert, optionally constraining acceptable CAs / signature algorithms. This is what turns the handshake into mTLS.
6. **Server `Finished`:** MAC over the handshake transcript.
7. **Client `Certificate`:** client sends its X.509 cert chain.
8. **Client `CertificateVerify`:** client signs the transcript hash with its private key, proving possession.
9. **Client `Finished`:** MAC over the transcript.
10. Both sides derive application traffic secrets and switch to encrypted application data.

Each side verifies the other's certificate chain against a trusted CA bundle (for mTLS this is typically a **private CA** specific to the fleet), checks validity period, SAN/CN, revocation (CRL/OCSP), and the `CertificateVerify` signature.

**Where mTLS is used in infrastructure:**
- **Service mesh** (Istio, Linkerd, Consul Connect) — automatic pod-to-pod encryption and identity.
- **Kubernetes control plane** — kubelet ↔ apiserver, apiserver ↔ etcd, controller-manager, scheduler all use mTLS with certs issued by the cluster CA.
- **Zero-trust networks** — SPIFFE/SPIRE identities, BeyondCorp-style internal services.
- **High-security APIs** — banking, healthcare, B2B webhooks where API key alone is insufficient.
- **IoT / device provisioning** — each device ships with its own client cert.

### D18 — Hard
**Answer:**
A **hash table** maps keys to values by applying a **hash function** to the key to get an integer, then taking it modulo the table size (or masking against `size-1` for power-of-two tables) to pick a **bucket** in an underlying array. The value is stored in that bucket. A good hash function distributes keys uniformly.

Because the range of the hash modulo size is smaller than the key space, **collisions** — two keys mapping to the same bucket — are inevitable. Two classic resolution strategies:

- **Separate chaining:** each bucket holds a secondary data structure (linked list, dynamic array, or a small tree — Java's `HashMap` switches to a red-black tree after a threshold). On collision, append to the bucket's chain. Simple; degraded buckets only hurt locally; tolerates high load factors.
- **Open addressing:** all entries live in the main array. On collision, probe for the next free slot using a deterministic sequence — **linear probing** (`h+1, h+2, ...`), **quadratic probing** (`h+1, h+4, h+9, ...`), or **double hashing** (`h + i*h2(k)`). Better cache locality, no pointer overhead, but suffers from primary/secondary clustering and requires keeping the load factor well below 1 (typically ≤0.7); deletions need tombstones.

To keep operations fast, hash tables **rehash** (double the array and re-insert) when the load factor exceeds a threshold. Most implementations also randomize the hash seed to defeat hash-flooding attacks.

**Complexity** (n entries, load factor α bounded by a constant):

| Operation | Average | Worst case |
|-----------|---------|------------|
| Insert    | O(1)    | O(n)       |
| Lookup    | O(1)    | O(n)       |
| Delete    | O(1)    | O(n)       |

Worst case O(n) happens when all keys collide into a single bucket (pathological hash function or adversarial input). Java's tree-binning reduces that to O(log n).

### D19 — Hard
**Answer:**
The **circuit breaker** pattern (popularized by Michael Nygard / Hystrix) wraps calls to a remote dependency and trips "open" when the dependency is unhealthy, short-circuiting subsequent calls so the caller fails fast instead of piling up threads on a dying downstream. This prevents **cascade failures** where one slow service saturates thread/connection pools upstream and takes down a whole chain of services.

**Three states:**
- **Closed:** normal operation. Every call is forwarded to the downstream. The breaker counts failures (errors, timeouts, 5xx) in a rolling window. If the failure rate or count crosses a threshold, it trips to **open**.
- **Open:** calls short-circuit immediately with a failure (or a fallback), without touching the downstream. A timer runs (e.g., 30 s "open timeout") so the downstream gets breathing room.
- **Half-open:** when the timer expires, a limited number of trial calls are allowed through. If they succeed, the breaker **closes**; if they fail, it returns to **open** and the timer restarts.

**Relationship to retries and exponential backoff:**
- **Retries** handle *transient* failures (one bad packet, one slow TCP handshake). Without a breaker, naive retries can amplify load on a struggling downstream — a known "retry storm" cascade.
- **Exponential backoff + jitter** spaces retries so clients don't synchronize hammer a recovering service.
- A **circuit breaker** caps the blast radius: once the breaker opens, no retries run at all until the open timer expires. Breakers and retries are complementary: retry a few times with backoff for transient blips, but let the breaker kill the traffic entirely when the downstream is genuinely down. In practice you combine breaker + bounded retries + jittered exponential backoff + timeout + bulkhead (isolated thread/connection pools).

### D20 — Hard
**Answer:**
- **Optimistic concurrency control (OCC):** assume conflicts are rare. Transactions read without acquiring locks, do their work, and at commit time check whether any of the rows they read have been modified by another transaction. If yes, the transaction is aborted and retried. Implemented via a **version column** (row versioning / MVCC) or timestamp.
- **Pessimistic concurrency control (PCC):** assume conflicts are common. Lock the rows you plan to modify as soon as you read them, so no one else can change them until you commit or roll back. Implemented via `SELECT ... FOR UPDATE` (or `FOR SHARE`) and explicit row/table locks.

**When to choose which:**
- **Optimistic:** short read-heavy transactions, low contention, web apps with many users viewing and few updating the same row, long user-think-time workflows where holding a lock would be expensive (wiki edits with "someone else modified this record" detection). Cheaper: no lock manager overhead, high throughput when conflicts are rare.
- **Pessimistic:** high-contention write paths where retrying is costly (long transactions with lots of work), or where conflict detection is hard (multiple coordinated updates, money transfers). Simpler semantics: you block and wait rather than replay.

**Concrete examples:**

Optimistic (row versioning, e.g., Postgres):

```sql
-- table: UPDATE accounts SET balance = 100, version = version + 1
--        WHERE id = 42 AND version = 7;
-- if rowcount == 0, someone else beat us; re-read, recompute, retry.
```

ORMs like Hibernate and JPA implement this via `@Version` fields. Elasticsearch uses `if_seq_no` / `if_primary_term` for the same purpose.

Pessimistic (PostgreSQL / MySQL InnoDB):

```sql
BEGIN;
SELECT balance FROM accounts WHERE id = 42 FOR UPDATE; -- row lock acquired
-- other transactions touching id=42 block here until we commit
UPDATE accounts SET balance = balance - 50 WHERE id = 42;
COMMIT;
```

`FOR UPDATE` takes an exclusive row lock; `FOR SHARE` takes a shared lock allowing other readers but blocking writers. Use it when you need to read a row, compute something, and update it atomically without the risk of a lost update.
