# Architecture Knowledge Test Suite — Answers

---

## Section 1: Application Architecture (AA1–AA12)

### AA1 — Easy
**Answer:**
A monolith is a single deployable unit where all application components (UI, business logic, data access) run in one process. Microservices decompose the application into independent services, each owning a bounded context and deployed separately. Three concrete problems microservices introduce: (1) network latency and unreliability — calls that were in-process function calls become network RPCs that can fail, timeout, or degrade; (2) distributed data consistency — without a shared database, keeping data consistent across services requires patterns like sagas or eventual consistency; (3) operational complexity — you now have dozens of deployable units requiring orchestration, service discovery, centralized logging, distributed tracing, and independent CI/CD pipelines that a monolith doesn't need.

### AA2 — Easy
**Answer:**
Synchronous communication means the caller blocks and waits for a response before continuing — the services are directly coupled in time. Example: HTTP/REST or gRPC, where Service A calls Service B and waits for a reply. Asynchronous communication decouples the sender from the receiver — the sender publishes a message and continues, and the receiver processes it later. Example: Apache Kafka or RabbitMQ, where Service A publishes an event to a topic/queue and doesn't know or care when Service B processes it. Async is more resilient (no cascading timeouts) but harder to debug (no direct request-response trace).

### AA3 — Medium
**Answer:**
A reverse proxy (e.g., nginx, HAProxy) operates at L4/L7 and forwards client requests to backend servers, handling TLS termination, load balancing, and static content serving. An API Gateway (e.g., Kong, AWS API Gateway) is a reverse proxy plus API-specific features: authentication/authorization, rate limiting, request transformation, API versioning, request/response validation, and developer portals. An API Gateway cannot fully replace a reverse proxy in all cases — high-throughput static file serving, TCP/UDP load balancing, and WebSocket-heavy workloads are often better handled by a purpose-built reverse proxy that has lower overhead and more granular L4 control. In practice, many architectures use both: a reverse proxy at the edge for TLS/LB and an API Gateway behind it for API management.

### AA4 — Medium
**Answer:**
The Saga pattern manages a distributed transaction across multiple services by breaking it into a sequence of local transactions, each with a compensating transaction for rollback. In choreography-based sagas, each service publishes events and other services react — there's no central coordinator. This is simpler and more decoupled but harder to reason about as the number of steps grows. In orchestration-based sagas, a central orchestrator (saga coordinator) tells each service what to do next and handles failure by executing compensating actions in reverse order. Choreography works well for simple 2-3 step flows (e.g., order → inventory → payment). Orchestration is better for complex flows with many steps or conditional branching (e.g., order → fraud check → inventory → payment → shipping → notification), because the workflow logic is explicit and debuggable in one place.

### AA5 — Medium
**Answer:**
CQRS separates the write model (commands) from the read model (queries) — each can use a different data model, schema, and even a different database optimized for its access pattern. Event Sourcing persists state as an immutable sequence of events rather than current-state snapshots. They're paired because the event log from Event Sourcing naturally feeds the read model projection — you replay events to build query-optimized views. This solves problems that CRUD doesn't: (1) complete audit trail — every state change is recorded, not just the final state; (2) temporal queries — you can answer "what was the state at time T?" by replaying events up to T; (3) independent read scaling — the read database can be denormalized, indexed differently, or even a different technology (e.g., Elasticsearch for search, Redis for dashboards) without affecting the write path. Trade-off: increased complexity and eventual consistency between write and read models.

### AA6 — Medium
**Answer:**
The Circuit Breaker pattern prevents cascading failures by stopping calls to a failing service after a threshold of failures is reached. It has three states: (1) Closed — requests pass through normally, failures are counted; (2) Open — requests are immediately rejected (fast-fail) without calling the downstream service; (3) Half-Open — after a timeout, a limited number of test requests are allowed through to check if the service has recovered. It differs from retry-with-backoff in that the circuit breaker actively stops traffic to protect both the caller and the failing service, while retry-with-backoff keeps trying (with increasing delays) and can make a degraded service worse by flooding it with retry requests. You'd use both together: the circuit breaker wraps a call that uses retry-with-backoff internally — so individual transient failures get retried, but if the service is consistently down, the circuit opens and stops all retries.

### AA7 — Hard
**Answer:**
**1. Shared database, shared schema (row-level tenant ID):** Lowest cost (one database, one schema), highest operational simplicity, but weakest security isolation — a query bug can leak tenant data, noisy neighbors share all resources (I/O, connections, cache), and schema migrations affect all tenants simultaneously. Best for early-stage SaaS with many small tenants and cost sensitivity.

**2. Shared database, separate schema per tenant:** Moderate cost (one database instance, N schemas), moderate complexity — migrations must run against each schema, connection pooling is trickier, but tenant data is logically isolated at the schema level (harder to accidentally cross-tenant query). Noisy neighbors still share the database engine's CPU/memory. Best for mid-tier SaaS where tenants need stronger data isolation but you don't want to manage N database instances.

**3. Separate database per tenant:** Highest cost (N database instances), highest operational complexity (N backups, N migrations, N monitoring), but strongest isolation — a noisy neighbor can't affect others, a compromised tenant's data is physically isolated, and you can tune each database independently (e.g., premium tenants get larger instances). Best for enterprise SaaS where tenants have compliance requirements (HIPAA, SOC2) or large tenants that justify dedicated infrastructure.

The choice is a spectrum: early-stage startups use option 1, mature B2B SaaS often lands on option 2 or 3 depending on tenant size and compliance needs.

### AA8 — Hard
**Answer:**
Strong consistency means every read returns the most recent write — all nodes agree on the current state before responding. Eventual consistency means reads might return stale data temporarily, but all replicas will converge to the same state given enough time and no new writes.

For a no-oversell inventory system at scale: use **strong consistency with optimistic concurrency control**. Data store choice: a CP (consistent, partition-tolerant) system like CockroachDB, Spanner, or PostgreSQL with serializable isolation. Pattern: decrement inventory atomically within the transaction (e.g., `UPDATE inventory SET qty = qty - 1 WHERE item_id = ? AND qty > 0`), and check the row count — if 0 rows updated, the item is sold out. For very high scale, add a reservation pattern: reserve inventory for a short window (e.g., 10 minutes) during checkout, release if not purchased. Redis with Lua scripts or Redlock can serve as a fast reservation layer in front of the durable store. Avoid eventual consistency here — a stale read could show 5 available when there are 0.

### AA9 — Hard
**Answer:**
A sidecar proxy is a separate container/process that runs alongside each application container in the same pod, handling network traffic on behalf of the application. In Istio, Envoy is the sidecar proxy — it intercepts all inbound and outbound traffic from the pod via iptables rules, so the application doesn't need to know about service mesh concerns.

The **data plane** consists of all the Envoy sidecar proxies handling actual request traffic. The **control plane** (Istiod) configures the Envoy proxies — it distributes routing rules, security policies, certificate management, and service discovery information to all sidecars.

mTLS between sidecars solves two things that application-level TLS doesn't: (1) it's transparent to the application — developers don't need to manage certificates in code; (2) it provides workload identity — each sidecar gets a SPIFFE identity, so you can enforce policies like "only services in namespace A can talk to services in namespace B" at the network layer, regardless of what the application does or doesn't implement. Application-level TLS only protects the app's own TLS endpoints and doesn't cover traffic the app didn't explicitly encrypt.

### AA10 — Medium
**Answer:**
The Strangler Fig pattern incrementally replaces a legacy system by routing specific functionality to new services while the rest continues running on the legacy system. Named after the fig tree that grows around a host tree until the host dies.

Concrete migration strategy for a .NET Framework monolith to .NET 8 microservices:

1. **Place a reverse proxy/API gateway in front of the monolith** — all external traffic routes through it. Initially, 100% goes to the monolith.
2. **Identify a bounded context to extract first** — pick something with low coupling and high value, e.g., the user notification system.
3. **Build the new service in .NET 8** — implement the notification API, deploy alongside the monolith.
4. **Route at the gateway** — update the gateway to send `/api/notifications/*` to the new service, everything else to the monolith. The monolith's notification code becomes dead code.
5. **Migrate data** — if the notifications use shared tables, create a new schema or database for the new service and migrate data. Use CDC (Change Data Capture) or dual-write during transition.
6. **Repeat** — extract bounded contexts one at a time: billing, user management, reporting. Each extraction reduces the monolith's surface area.
7. **Decommission** — when the monolith has no remaining active routes, decommission it.

The key advantage is zero big-bang cutover — the system runs continuously throughout the migration.

### AA11 — Medium
**Answer:**
The 12-Factor App methodology (Heroku, 2011) defines best practices for building cloud-native, scalable, maintainable applications. Six key factors:

1. **Codebase** — One codebase tracked in version control, many deploys. The same artifact is promoted through environments, not rebuilt per environment.
2. **Dependencies** — Explicitly declare and isolate dependencies (e.g., `package.json`, `requirements.txt`, `go.mod`). Never rely on system-wide packages.
3. **Config** — Store config (DB credentials, API keys, feature flags) in environment variables, not in code. This enables the same artifact to run in dev/staging/prod with different configs.
4. **Backing services** — Treat databases, caches, SMTP servers as attached resources accessed via URL in config. Swapping a backing service (e.g., MySQL → Postgres) is a config change, not a code change.
5. **Disposability** — Processes are disposable: fast startup and graceful shutdown. This enables elastic scaling and resilience — a crashed process is replaced without drama.
6. **Logs** — Treat logs as event streams written to stdout. The execution environment (Kubernetes, Cloud Foundry) handles routing to aggregation systems. The app doesn't write log files.

These matter for cloud-native because they enable horizontal scaling, environment portability, and resilience in containerized/orchestrated environments.

### AA12 — Hard
**Answer:**
**Coupling:** Event-driven with Kafka is loosely coupled — producers don't know consumers, and new consumers can be added without changing producers. REST/gRPC is tightly coupled — callers must know the callee's API, and changes can break callers.

**Scalability:** Kafka scales by adding partitions and consumers — consumers can be scaled independently of producers. REST/gRPC requires the service itself to scale (more replicas behind a load balancer) and scales both directions symmetrically.

**Debugging complexity:** REST/gRPC is easier to debug — a request flows linearly and you can trace it with a correlation ID. Event-driven is harder — a single business transaction may span multiple topics, consumers, and time delays; you need distributed tracing (OpenTelemetry) and event lineage tools.

**Ordering guarantees:** Kafka guarantees ordering within a partition (key-based). REST/gRPC has no inherent ordering — each request is independent. For ordered processing in REST, you need a queue or sequence number.

**Failure handling:** REST/gRPC gives immediate failure feedback (HTTP 500, timeout) and the caller can decide what to do. In Kafka, failures are handled by the consumer — retries, dead-letter queues, and the system can tolerate temporary consumer outages without losing data.

**When to choose:** Use event-driven/Kafka when you need loose coupling, high throughput, temporal decoupling (producer and consumer don't need to be online simultaneously), or event replay. Use REST/gRPC when you need synchronous responses (user-facing APIs), simple request-response patterns, strong typing (gRPC/Protobuf), or low-latency RPC between internal services.

---

## Section 2: On-Premise Infrastructure Architecture (OP1–OP12)

### OP1 — Easy
**Answer:**
Type 1 (bare-metal) hypervisors run directly on the hardware without a host OS, managing hardware resources and VMs directly. They offer better performance and lower latency because there's no host OS overhead. Examples: VMware ESXi, Microsoft Hyper-V, Proxmox VE (KVM-based), Xen. Type 2 (hosted) hypervisors run as an application on top of a host OS, and VMs run inside them. They're easier to install and use but add an extra layer of overhead. Examples: VMware Workstation, VirtualBox, Parallels Desktop. Type 1 is used in production data centers; Type 2 is used for development, testing, and desktop virtualization.

### OP2 — Easy
**Answer:**
A SAN (Storage Area Network) provides block-level storage — the server sees raw disk blocks and formats them with its own filesystem. SANs use Fibre Channel (FC) or iSCSI protocols. Use SAN when applications need high-performance, low-latency block access (databases, virtual machine disks). A NAS (Network Attached Storage) provides file-level storage via NFS or SMB/CIFS — clients mount a shared filesystem. Use NAS when multiple clients need to access the same files (home directories, shared document storage, media files). SAN is more expensive and complex but faster; NAS is simpler and cheaper for file sharing.

### OP3 — Medium
**Answer:**
A 3-tier network architecture has core switches (backbone routing), distribution/aggregation switches (policy enforcement, VLAN routing), and access switches (end device connections). Traffic flows access → distribution → core → distribution → access. This creates a tree topology with a single path between any two devices, leading to oversubscription at the uplinks and blocked redundant links via STP (Spanning Tree Protocol).

Leaf-spine fixes this: every leaf switch connects to every spine switch (full mesh), creating a predictable, low-latency fabric with exactly one hop between any two leaf switches. It eliminates STP by using ECMP (Equal-Cost Multi-Path) routing to distribute traffic across all spine links. The problem it solves: (1) non-blocking bandwidth — no single oversubscribed uplink; (2) predictable latency — always 2 hops leaf→spine→leaf; (3) horizontal scaling — add more spine switches for bandwidth, add more leaf switches for port density, without redesigning the topology. This is why every major cloud provider and modern data center uses leaf-spine.

### OP4 — Medium
**Answer:**
A highly available Proxmox cluster architecture:

**Node count:** Minimum 3 nodes for quorum (Proxmox uses Corosync for cluster quorum — needs a majority, so 3 nodes tolerates 1 failure, 5 tolerates 2). Add a QDevice (tiebreaker) if running 2 nodes in a small setup.

**Quorum:** Corosync maintains quorum via heartbeat on the cluster network. If a node loses quorum (network partition), it stops its VMs to prevent split-brain (the `pvecm` quorum daemon handles this).

**Fencing:** Proxmox uses watchdog-based fencing — if a node becomes unresponsive, the watchdog timer triggers a reboot. For hardware-level fencing, configure IPMI/iDRAC fencing so the cluster can forcibly power-cycle a hung node.

**Shared storage options:**
- **Ceph (hyperconverged):** Built into Proxmox, replicates data across nodes (3 replicas recommended). Best for HA — if a node dies, VMs restart on another node with data already there. Trade-off: requires fast networking (10GbE+) and 3+ nodes.
- **iSCSI:** Centralized SAN accessed by all nodes. VMs can live-migrate. Single point of failure unless the SAN itself is HA.
- **NFS:** Simple shared storage. Lower performance than iSCSI/Ceph. Single point of failure.

**Node failure scenario:** If Node 2 dies, Corosync detects the heartbeat loss within ~10 seconds. Quorum is maintained (2 of 3 nodes). The cluster marks Node 2 as offline. With Ceph, the VM that was running on Node 2 is restarted on Node 1 or 3 using the replicated data. HA groups control which VMs failover and to which nodes.

### OP5 — Medium
**Answer:**
VLAN trunking allows a single physical link to carry traffic for multiple VLANs by tagging each Ethernet frame with a VLAN ID using the 802.1Q standard. 802.1Q inserts a 4-byte tag into the Ethernet frame header containing a 12-bit VLAN ID field (supporting VLANs 1-4094). An access port carries traffic for a single VLAN (untagged); a trunk port carries multiple VLANs (tagged).

On Linux, configure a single NIC for 3 VLANs using sub-interfaces:
```bash
# Assuming NIC is eth0, VLANs are 10, 20, 30
ip link add link eth0 name eth0.10 type vlan id 10
ip link add link eth0 name eth0.20 type vlan id 20
ip link add link eth0 name eth0.30 type vlan id 30

ip addr add 10.0.10.5/24 dev eth0.10
ip addr add 10.0.20.5/24 dev eth0.20
ip addr add 10.0.30.5/24 dev eth0.30

ip link set eth0.10 up
ip link set eth0.20 up
ip link set eth0.30 up
```
Or persist via `/etc/network/interfaces` with `vlan-raw-device` or systemd-networkd `.netdev` files. The switch port must be configured as a trunk port allowing VLANs 10, 20, 30.

### OP6 — Medium
**Answer:**
**RAID 1** mirrors data across 2 drives — 50% capacity, excellent read performance, survives 1 drive failure. **RAID 5** stripes data with distributed parity across N drives — survives 1 failure, (N-1)/N capacity, poor write performance due to parity calculation. **RAID 6** like RAID 5 but with double parity — survives 2 simultaneous failures, (N-2)/N capacity, even worse write performance. **RAID 10** mirrors then stripes — survives at least 1 failure (possibly more depending on which drives), 50% capacity, excellent read/write performance. **RAID Z2** (ZFS) is analogous to RAID 6 — double parity, survives 2 failures, but with ZFS's checksumming and self-healing.

**For a database server with 6 drives: choose RAID 10.** Reasoning: databases are write-heavy and latency-sensitive. RAID 5/6 have a write penalty (read-modify-write cycle for small random writes) that kills database performance. RAID 10 gives the best write IOPS (writes go to mirrored pairs, no parity calculation), survives 1 drive failure minimum, and rebuilds are fast (just copy from mirror, not reconstruct from parity across all drives). The trade-off is 50% capacity vs 67% for RAID 5 or 83% for RAID 6, but for a database, performance and fast rebuilds outweigh capacity.

### OP7 — Hard
**Answer:**
DNS architecture for a 500-person enterprise:

**Components:**
- **Internal DNS:** Two AD-integrated DNS servers (on the Domain Controllers) handling the internal zone (`corp.example.com`). These are authoritative for the internal zone and recursive for external queries.
- **External DNS:** Two authoritative-only DNS servers in the DMZ for the public zone (`example.com`), with DNSSEC signing enabled. These do NOT resolve internal queries.
- **Recursive resolvers:** Two dedicated recursive resolvers (e.g., Unbound or Windows DNS in caching mode) for internal clients. These forward to internal DNS for `corp.example.com` and to external forwarders (e.g., 1.1.1.1, 8.8.8.8) for everything else.
- **Split-horizon:** Internal clients get private IPs for internal services (e.g., `vpn.example.com` → 10.0.1.5). External clients get public IPs for the same names (e.g., `vpn.example.com` → 203.0.113.5). This is achieved by having separate DNS zones/views.
- **Conditional forwarding:** For partner domains or Azure AD DNS, configure conditional forwarders on the internal DNS servers to forward specific zones to the appropriate DNS servers.

**Laptop on office vs VPN:** On the office network, the laptop gets DHCP with internal recursive resolvers as DNS servers — all queries go through internal DNS. When the user connects via VPN, the VPN client pushes the internal DNS servers as the primary resolvers (via split-tunnel DNS or full-tunnel). If using split-DNS (Windows NRPT or equivalent), queries for `corp.example.com` go through the VPN to internal DNS, while everything else resolves via the local internet DNS. The laptop's DNS suffix search list includes `corp.example.com` so unqualified names resolve against the internal zone.

### OP8 — Hard
**Answer:**
**PKI chain of trust:** The root CA is the trust anchor — it self-signs its own certificate. The root CA signs one or more subordinate (issuing) CAs. Subordinate CAs issue end-entity certificates (servers, clients, code signing). Each certificate in the chain is validated by verifying the issuer's signature up to the root, which the client trusts because it's in the trusted root store.

**Internal PKI deployment:**
- **Root CA:** Offline, air-gapped, powered on only to sign subordinate CA certificates or perform CRL signing. Store in a physical safe. Use an HSM for key protection. Certificate lifetime: 20-30 years.
- **Subordinate/issuing CA:** Online, issues end-entity certificates. Certificate lifetime: 5-10 years. Can be revoked by the root CA if compromised.
- **CRL vs OCSP:** CRL (Certificate Revocation List) is a periodically published list of revoked serial numbers — simple but has latency (next CRL publish). OCSP (Online Certificate Status Protocol) provides real-time revocation checking by querying the CA — faster but requires the OCSP responder to be highly available.
- **Certificate templates:** Define certificate properties (key usage, SAN, validity period, enrollment permissions) for different use cases (web server, client auth, code signing).
- **Auto-enrollment:** Via Group Policy (AD CS) or SCEP/EST protocols — domain-joined machines automatically request and renew certificates without manual intervention.

**Compromise consequences:** A compromised subordinate CA is serious but recoverable — revoke the subordinate CA's certificate (issue a CRL from the root), deploy a new subordinate CA, and reissue all certificates. The root remains trusted. A compromised root CA is catastrophic — every certificate in the entire PKI is untrustworthy. You must generate a new root CA, redistribute it to all trust stores (every device, every application), and reissue every certificate. This can take months and requires touching every system.

### OP9 — Hard
**Answer:**
WAN consolidation for 5 remote offices (50 users/site, latency-sensitive VoIP):

**MPLS:** Provider-managed, QoS-aware, reliable. Guaranteed bandwidth and latency SLAs. Expensive ($500-2000/month per site depending on bandwidth). No encryption by default (add IPsec overlay). Slow provisioning (weeks). Best for enterprises that need guaranteed VoIP quality and have budget.

**IPsec VPN over internet:** Cheap (just internet links), encrypted, self-managed. No QoS guarantees — VoIP quality depends on internet path quality. Can be unreliable during internet congestion. Requires managing tunnel endpoints, routing, and failover. Best for cost-sensitive deployments without strict latency requirements.

**SD-WAN:** Intelligent overlay that uses multiple internet links (broadband, LTE, MPLS) and dynamically steers traffic based on application policy. VoIP traffic can be pinned to the lowest-latency path with QoS marking. Built-in encryption, centralized management, zero-touch provisioning. Cost: $100-500/month per site (software license) plus internet links. Best for most mid-size companies — combines cost savings of internet with application-aware routing.

**WireGuard mesh:** Lightweight, fast, modern VPN. Extremely low overhead and latency (kernel-space implementation). Simple configuration. But: no centralized management, no built-in QoS, no application-aware routing. You'd build your own orchestration. Best for small deployments with technical staff.

**Recommendation: SD-WAN.** For 5 sites with 50 users and VoIP, SD-WAN provides the best balance: it uses cheap internet links, provides application-aware routing to prioritize VoIP, offers centralized management (critical for a small IT team), and has built-in failover (dual internet links per site). MPLS is overkill and too expensive for 250 total users. IPsec alone lacks QoS. WireGuard is too DIY.

### OP10 — Medium
**Answer:**
iDRAC (Dell), iLO (HPE), and IPMI (generic) are out-of-band management interfaces — independent processors with their own network interface that allow remote management of a server regardless of the OS state. They provide: remote power control (on/off/reset), console redirection (KVM over IP — see the screen remotely), hardware health monitoring (temperature, fan speed, disk status), virtual media mounting (boot from an ISO remotely), and BIOS/firmware configuration.

Out-of-band management is critical because: (1) you can recover a server that has crashed, hung at POST, or has a misconfigured OS — things that in-band management (SSH/RDP) can't reach; (2) you can install an OS from scratch on bare metal; (3) you can diagnose hardware failures without physical access to the data center.

If IPMI/iDRAC is exposed to the internet, it's a critical security risk: these interfaces often have default credentials, run outdated firmware with known vulnerabilities, and don't have brute-force protection. An attacker with access can power-cycle servers, mount malicious ISOs, capture console output (including passwords), or use the BMC as a pivot point into the management network. Always isolate IPMI on a dedicated management VLAN, never route it to the internet, and change default credentials.

### OP11 — Medium
**Answer:**
**LVM (Logical Volume Manager):** Linux kernel subsystem that abstracts physical disks into volume groups and logical volumes. Supports online resizing, spanning multiple disks, and basic snapshots (uses copy-on-write, requires space in the VG for snapshot delta). Snapshots are performance-intensive during heavy writes. Widely supported, mature.

**LVM-Thin:** Thin-provisioned LVM — logical volumes are allocated on-demand rather than pre-allocating all space. Snapshots are space-efficient (only store changes). The trade-off is overcommitment risk — if all thin volumes actually write their full allocated size, you run out of physical space and volumes can be corrupted. Requires a thin pool.

**ZFS:** Combined filesystem and volume manager with built-in RAID (RAIDZ), compression, checksumming, copy-on-write snapshots (instant, space-efficient, no performance penalty), and self-healing (detects and repairs bit rot using checksums). Snapshots are first-class — O(1) creation, independent of data size. ZFS requires significant RAM (1GB per TB of storage is a common guideline). Best for data integrity and snapshot-heavy workloads (backups, VM storage, NAS).

**When to use:** LVM for general-purpose Linux disk management when you don't need advanced features. LVM-Thin when you need space-efficient snapshots in Proxmox (Proxmox uses this by default for VM disks). ZFS when data integrity matters (checksums against bit rot), you need frequent instant snapshots, or you're building a NAS/storage server.

### OP12 — Hard
**Answer:**
**Stretch cluster / DR for 3-node Proxmox + Ceph across two sites:**

**The problem:** Ceph needs a majority of OSDs (Object Storage Daemons) to write data. With a 2-site deployment, if the inter-site link fails, neither site has a majority — split-brain. Writes halt on both sides. This is why 2-site Ceph without a tiebreaker is a bad idea.

**Stretch cluster solution (Ceph 16+):**
- 2 data sites (Site A, Site B) plus 1 tiebreaker/witness site (Site C) with a single monitor
- Ceph crush rule: `stretch` mode with `pool size 4` — 2 replicas in each data site, and the tiebreaker monitor breaks quorum
- Data is replicated 2+2 across sites (2 copies at each site)
- If Site A loses connectivity, Site B + tiebreaker maintain quorum and continue serving I/O
- If the tiebreaker monitor is lost, both data sites continue (they each have 2 of 4 replicas)

**Ceph CRUSH rules:** Configure a CRUSH rule that places replicas across failure domains (hosts → racks → rooms → sites). For stretch: `step chooseleaf firstn 2 type room` ensures 2 replicas per room (site).

**Monitor placement:** At least 1 monitor per data site + 1 at the tiebreaker site = 3 monitors total. Monitors need sub-100ms latency between sites for quorum stability.

**Network latency requirements:** Ceph stretch mode recommends <5ms RTT between data sites for acceptable OSD performance. Higher latency causes slow I/O and OSD timeouts.

**DR alternative (non-stretch):** If sites are far apart (>5ms), use asynchronous replication via RBD mirroring (Ceph's built-in async mirroring) instead of a stretch cluster. Accept data loss of seconds-to-minutes (RPO) during failover, but sites can be any distance apart. This is simpler and more tolerant of high latency.

---

## Section 3: Cloud Infrastructure Architecture (CL1–CL12)

### CL1 — Easy
**Answer:**
**IaaS (Infrastructure as a Service):** You rent virtual machines, storage, and networking. You manage the OS, middleware, runtime, and application. Example: AWS EC2, Azure Virtual Machines, Google Compute Engine.

**PaaS (Platform as a Service):** You deploy your application code; the provider manages the OS, runtime, and scaling. You manage the application and data. Example: AWS Elastic Beanstalk, Azure App Service, Google App Engine.

**SaaS (Software as a Service):** You consume a finished application via the internet. The provider manages everything. Example: Microsoft 365, Salesforce, Google Workspace.

The key distinction is the boundary of what you manage: IaaS = most control, most responsibility. SaaS = least control, least responsibility.

### CL2 — Easy
**Answer:**
The Shared Responsibility Model defines where the cloud provider's security responsibility ends and the customer's begins.

**IaaS VMs (e.g., EC2):** Provider manages physical infrastructure, hypervisor, and global network. Customer manages OS patching, firewall rules (security groups), IAM, application security, and data encryption. The customer owns nearly everything above the hypervisor.

**Managed Kubernetes (e.g., EKS, AKS):** Provider manages the control plane (API server, etcd, scheduler), control plane patching, and availability. Customer manages worker node OS, pod security, RBAC, network policies, workload configuration, and container image security. The split is more nuanced — the provider owns the "Kubernetes-as-a-service," the customer owns the workloads running on it.

**SaaS (e.g., M365):** Provider manages everything from infrastructure to application. Customer manages: user identity/access (who can log in), data classification (what you put in), and configuration (sharing policies, retention policies). Customer responsibility shrinks to identity and data governance.

### CL3 — Medium
**Answer:**
**VPC (Virtual Private Cloud):** An isolated virtual network in the cloud — you define the IP address range (CIDR), subnets, routing, and gateways. It's the network boundary for your cloud resources.

**Subnet:** A segment of a VPC's IP range, associated with an availability zone. Resources (EC2 instances, etc.) are placed in subnets. Subnets are classified as public (has a route to an internet gateway) or private (no direct internet route).

**Security Group:** A stateful virtual firewall attached to individual resources (ENIs/instances). You define inbound and outbound rules. Stateful means if you allow inbound traffic, the response is automatically allowed outbound regardless of outbound rules. Operates at the instance level.

**NACL (Network ACL):** A stateless firewall at the subnet level. You define numbered rules for inbound and outbound traffic. Stateless means you must explicitly allow both inbound AND the response outbound. NACLs are evaluated before security groups.

**Layering:** Traffic hits the NACL first (subnet-level, stateless), then the security group (instance-level, stateful). Use NACLs for broad subnet-level rules (e.g., block a specific IP range) and security groups for application-level rules (e.g., allow port 443 from anywhere). Security groups are the primary firewall mechanism in practice — NACLs are a secondary defense layer.

### CL4 — Medium
**Answer:**
**Multi-account strategy (AWS/Azure) for a mid-size company:**

**Landing zone concept:** A pre-configured, secure, multi-account environment with guardrails, networking, logging, and identity baked in from the start. AWS Control Tower or Azure Landing Zones provide this as a framework.

**Organizational units (OUs):** Logical groupings of accounts by function. Example structure:
- Security OU: Log archive account, security tooling account
- Shared Services OU: Networking account (Transit Gateway), CI/CD account
- Workload OU: Dev account, Staging account, Production account
- Sandbox OU: Experimentation accounts with strict spending limits

**Guardrails:** Preventive guardrails (SCPs in AWS, Azure Policies) block actions like disabling CloudTrail or creating public S3 buckets. Detective guardrails (Config rules, Security Hub) alert on violations. Apply at the OU level so all accounts inherit them.

**Shared networking:** Transit Gateway (AWS) or Hub-and-Spoke VNet (Azure) connects accounts. The networking account owns the Transit Gateway, firewall, VPN/Direct Connect. Spoke accounts peer to it. Centralized internet egress through a shared firewall for inspection and logging.

**Centralized logging:** All accounts ship CloudTrail/VPC Flow Logs to the log archive account. Security tools (SIEM) run in the security account and read from the central log bucket.

**Why single-account is problematic:** Blast radius (compromise affects everything), noisy neighbor (one workload's traffic impacts others), billing visibility (hard to attribute costs), permission boundaries (hard to enforce least privilege when everything shares an account), and compliance scope (auditing one account means auditing everything).

### CL5 — Medium
**Answer:**
**Infrastructure as Code (IaC)** defines and provisions infrastructure through machine-readable configuration files rather than manual console clicks, enabling version control, repeatability, and auditability.

**Comparison:**

| Tool | Language | Model | Best For |
|------|----------|-------|----------|
| Terraform/OpenTofu | HCL (declarative) | State file, plan/apply | Multi-cloud, large teams, provider ecosystem (3000+ providers) |
| Pulumi | Python/TypeScript/Go (imperative → declarative) | State file, plan/apply | Teams that want real programming languages, complex logic in IaC |
| CloudFormation/Bicep | JSON/YAML (CF) or Bicep DSL (declarative) | Native AWS/Azure state | Single-cloud shops wanting tight provider integration and no external state |
| Crossplane | Kubernetes CRDs (declarative) | Kubernetes controller, reconciliation | Teams already deep in Kubernetes wanting cloud infra managed like K8s resources |

**When to choose:** Terraform/OpenTofu for multi-cloud or when you want the largest ecosystem. Pulumi when your team prefers real programming languages over DSLs. CloudFormation/Bicep when you're all-in on one cloud and want native tooling. Crossplane when you want infrastructure lifecycle managed by Kubernetes controllers and your ops team thinks in kubectl.

### CL6 — Medium
**Answer:**
**HPA (Horizontal Pod Autoscaler):** Scales the number of pod replicas based on CPU/memory utilization or custom metrics. Standard choice for stateless workloads. Configured with target utilization thresholds (e.g., scale up when average CPU > 70%).

**VPA (Vertical Pod Autoscaler):** Adjusts the CPU/memory resource requests and limits of existing pods. Useful when you don't know the right resource allocation upfront or for workloads that can't easily scale horizontally (monolithic apps, single-replica stateful services). Trade-off: may require pod restart to apply new resource limits.

**Cluster Autoscaler:** Scales the underlying node pool (add/remove nodes) when pods are pending due to insufficient cluster capacity. Works with HPA — HPA scales pods, Cluster Autoscaler scales nodes to fit them.

**KEDA (Kubernetes Event-Driven Autoscaler):** Extends HPA with event-driven triggers from external sources: Kafka consumer lag, RabbitMQ queue depth, Azure Service Bus messages, Prometheus metrics, cron schedules, etc. Use KEDA over HPA when: (1) you need to scale based on external event sources rather than CPU/memory (e.g., "scale workers when Kafka lag > 1000 messages"); (2) you need scale-to-zero (KEDA supports scaling to 0 replicas when there are no events, which HPA doesn't do by default); (3) you have heterogeneous trigger sources that don't fit standard CPU/memory metrics.

### CL7 — Hard
**Answer:**
**Disaster recovery strategy for cloud-native across two regions:**

**RPO (Recovery Point Objective):** Maximum acceptable data loss. RTO (Recovery Time Objective): Maximum acceptable downtime. These drive every design decision.

**DR patterns from cheapest to most expensive:**

1. **Backup & Restore:** RPO hours, RTO hours. Take periodic backups, restore in DR region during disaster. Cheapest but slowest.
2. **Pilot Light:** RPO minutes, RTO 10s of minutes. Core data replicated to DR region, but compute infrastructure is minimal (just the database running). During disaster, spin up application servers from pre-built AMIs/images.
3. **Warm Standby:** RPO minutes, RTO minutes. A scaled-down copy of production runs in DR region. Data replicated asynchronously. During disaster, scale up the DR region. Higher cost than pilot light because you're running some compute continuously.
4. **Multi-site Active-Active:** RPO near-zero, RTO near-zero. Both regions serve traffic simultaneously. Data replicated synchronously (or near-sync). Highest cost, highest complexity.

**Database replication:** Synchronous replication ensures zero data loss (RPO=0) but adds latency to writes (both regions must confirm). Async replication is faster but introduces data loss window (RPO = replication lag). For active-active, consider conflict resolution (last-writer-wins, CRDTs, or application-level conflict handling).

**DNS failover:** Route53 health checks (AWS) or Traffic Manager endpoints (Azure) monitor the primary region. When health checks fail, DNS TTL expires and clients are routed to the DR region. This is the RTO bottleneck — TTL dictates how quickly clients switch. Lower TTL (30-60s) means faster failover but more DNS query costs.

**State management:** Stateless services are easy to failover — just run replicas in DR. Stateful services need data replication. Session state should go to a replicated store (Redis with replication, DynamoDB Global Tables). Avoid local disk state.

**Cost implications:** Active-active is 2x+ the compute cost of single-region. Pilot light is ~1.1-1.3x (just storage and minimal compute). Warm standby is ~1.5-2x depending on standby scale factor.

### CL8 — Hard
**Answer:**
**GitOps** is an operational model where the desired state of infrastructure and applications is declared in Git, and an agent continuously reconciles the actual state with the desired state. Changes happen via pull requests, not kubectl.

**ArgoCD vs FluxCD:**
- **ArgoCD:** Provides a UI dashboard, multi-cluster management, RBAC, application sets for templating, and sync waves for ordered deployment. More feature-rich out of the box. Heavier footprint (runs a UI server). Better for teams that want visibility and a management plane.
- **FluxCD:** Lightweight, composable (individual controllers for source, kustomize, helm, notification). No built-in UI (use Weave GitOps or Grafana dashboards). Better for teams that prefer minimal components and want to build their own management layer. FluxCD's image automation controller can auto-update image tags in Git when new images are pushed.

**Secrets management:**
- **Sealed Secrets:** Encrypts Kubernetes secrets client-side; the cluster has the key to decrypt. Secrets are safe to commit to Git. Limitation: must be decrypted in-cluster, can't be used outside K8s.
- **External Secrets Operator (ESO):** Syncs secrets from external providers (Vault, AWS Secrets Manager, Azure Key Vault) into Kubernetes Secrets. Secrets aren't stored in Git — just references to where they live.
- **Vault + Agent Injector:** HashiCorp Vault injects secrets directly into pods at runtime. Most secure (secrets never touch Git or K8s etcd plaintext) but most complex to operate.

**Drift handling:** When someone makes a manual change (e.g., `kubectl edit deployment`), the GitOps agent detects the drift on the next reconciliation loop and reverts the change back to match the Git state. This is a feature, not a bug — it enforces that Git is the single source of truth. ArgoCD shows drift in the UI and can be configured to auto-sync or alert. If the manual change is actually desired, it must be committed to Git first.

### CL9 — Hard
**Answer:**
**Kubernetes architecture for a stateful legacy app with local storage, sticky sessions, ordered startup, and config files:**

**StatefulSet** (not Deployment) — provides stable network identity (pod-0, pod-1), ordered deployment (pod-0 ready before pod-1 starts), ordered termination (pod-1 before pod-0), and persistent storage per pod via volumeClaimTemplates.

**Storage:**
```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    storageClassName: local-storage  # or local-path
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 100Gi
```
Use a `local` StorageClass backed by node-local SSDs. Requires a PV provisioner (e.g., local-path-provisioner) that creates PVs on the node's disk. Pod affinity ensures the pod is scheduled on the node that has the PV data.

**Headless service** for stable DNS:
```yaml
spec:
  clusterIP: None
```
Each pod gets a stable DNS name: `app-0.headless-svc.namespace.svc.cluster.local`. Use this for inter-pod communication and sticky sessions.

**Sticky sessions:** Use a StatefulSet with an external load balancer that supports session affinity (e.g., nginx ingress with `affinity: cookie`), or use the stable pod DNS names directly with a client-side load balancer that hashes to specific pods.

**Init containers** for ordered startup:
```yaml
initContainers:
- name: wait-for-dependency
  image: busybox
  command: ['sh', '-c', 'until nslookup db-0.db-svc; do sleep 2; done']
```
Init containers run before the main container, ensuring dependencies (like pod-0 of a database) are ready before the application starts.

**ConfigMaps as volume mounts:**
```yaml
volumes:
- name: config
  configMap:
    name: app-config
containers:
- name: app
  volumeMounts:
  - name: config
    mountPath: /etc/app/config.yaml
    subPath: config.yaml
```
This maps the ConfigMap data to the exact filesystem path the legacy app expects. `subPath` avoids replacing the entire directory.

**Pod Disruption Budget:**
```yaml
spec:
  minAvailable: 2  # or maxUnavailable: 1
  selector:
    matchLabels:
      app: my-stateful-app
```
Prevents voluntary disruptions (node drain, cluster upgrade) from taking down too many pods simultaneously.

### CL10 — Medium
**Answer:**
**Service account:** A Kubernetes-native identity (SA) assigned to a pod. It gets a JWT token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/`. This identifies the pod to the Kubernetes API server — it says "who am I within K8s," but says nothing to external cloud providers.

**Workload identity:** Federates a Kubernetes service account with a cloud provider identity. The K8s SA token is exchanged for a cloud provider access token without storing credentials. This bridges "who am I in K8s" to "who am I in AWS/Azure/GCP."

**IRSA (IAM Roles for Service Accounts — AWS specific):** AWS's implementation of workload identity. An IAM role has a trust policy that trusts a specific OIDC provider (the EKS cluster's OIDC issuer) and a specific service account. When the pod's SA token is presented to AWS STS, it receives temporary IAM credentials for that role. Azure's equivalent is Workload Identity Federation; GCP's is Workload Identity.

**Why mounting cloud credentials in a pod is bad:** (1) Credentials are stored as Kubernetes secrets (base64, not encrypted by default in etcd); (2) any pod in the namespace can potentially mount the same secret; (3) long-lived credentials can be stolen and reused from anywhere; (4) credential rotation requires updating the secret and restarting pods; (5) no audit trail of which specific pod used the credential.

**How workload identity solves this:** No credentials are stored anywhere. The pod presents its K8s SA token (which is short-lived and audience-restricted) to the cloud provider's STS/identity endpoint, which validates the token against the OIDC provider and issues short-lived, scoped credentials. Each pod gets its own temporary credentials tied to its specific service account. If the pod dies, the credentials expire automatically. Rotation is automatic.

### CL11 — Medium
**Answer:**
**Object storage (S3, Azure Blob, GCS):** Stores unstructured data as objects (blobs) in a flat namespace (buckets/containers) with metadata. Accessed via HTTP REST API. Infinitely scalable, pay-per-use, 11-16 nines durability. No file locking, eventual consistency for overwrites (strong for new objects in S3). Use for: static assets, backups, data lakes, media storage, log archives, ML training data.

**Block storage (EBS, Azure Managed Disk, GCP Persistent Disk):** Provides raw block devices attached to VMs. The VM OS formats it with a filesystem. High IOPS, low latency. Can only be attached to one VM at a time (except EBS multi-attach). Use for: database storage, VM boot disks, any workload needing a traditional filesystem with high performance.

**File storage (EFS, Azure Files, GCP Filestore):** Provides a shared NFS/SMB filesystem accessible by multiple instances simultaneously. Managed NFS with automatic scaling. Lower IOPS than block storage but enables shared access. Use for: shared content (web server assets), home directories, legacy applications that require a POSIX filesystem shared across machines, lift-and-shift of on-prem file shares.

**Durability and availability:** S3 standard: 99.999999999% (11 nines) durability, 99.99% availability. EBS: 99.999% durability, 99.99% availability (within an AZ). EFS: 99.999999999% (11 nines) durability, 99.99% availability.

### CL12 — Hard
**Answer:**
**Zero-trust network architecture for Kubernetes in the cloud:**

**Core principle:** Never trust, always verify. No implicit trust based on network location (unlike perimeter models where "inside the firewall = trusted").

**Components:**

1. **Network Policies:** Kubernetes NetworkPolicies define which pods can communicate. Default-deny all ingress/egress, then explicitly allow required flows. Example: only pods with label `role=frontend` can talk to pods with label `role=backend` on port 8080. This implements microsegmentation at the pod level.

2. **Service mesh with mTLS:** Istio/Linkerd injects sidecar proxies that enforce mutual TLS between all pods. Every service has a cryptographic identity (SPIFFE). Even if an attacker is inside the cluster, they can't sniff traffic or impersonate services without a valid certificate. mTLS also enables authorization policies (e.g., "only namespace A can call namespace B").

3. **Pod identity:** Use workload identity (IRSA, Azure Workload Identity) so pods get short-lived, scoped cloud credentials without stored secrets. Each pod has a cryptographic identity both within the cluster (mTLS) and to external cloud services.

4. **Admission controllers (OPA/Gatekeeper or Kyverno):** Policy enforcement at the API server level. Reject non-compliant resources before they're created. Examples: block containers running as root, require resource limits, enforce image signing, require network policies, block privileged containers.

5. **Image signing and verification:** Use Sigstore/cosign to sign container images during CI. Admission controller (Kyverno or Connaisseur) verifies signatures before allowing pod creation. Only signed images from trusted registries run. Prevents supply chain attacks.

6. **Runtime security (Falco):** Monitors system calls inside running containers. Detects anomalous behavior: unexpected process execution, file access in sensitive paths, network connections to suspicious IPs. Alerts or kills pods on detection.

7. **Secrets management:** External Secrets Operator syncs secrets from Vault/AWS SM into K8s at runtime. Secrets never stored in Git. Vault provides dynamic secrets (database credentials that auto-expire).

**Contrast with perimeter model:** Traditional security assumes internal traffic is trusted — firewall at the edge, flat internal network. Zero-trust assumes the network is compromised — every request is authenticated, authorized, and encrypted regardless of source. In a perimeter model, a compromised pod can move laterally freely. In zero-trust, network policies block lateral movement, mTLS prevents traffic interception, and admission policies prevent privilege escalation.

---

## Section 4: OT Infrastructure Architecture (OT1–OT12)

### OT1 — Easy
**Answer:**
The Purdue Model (ISA-95) is a reference architecture for industrial network segmentation that organizes OT/IT systems into hierarchical levels:

- **Level 0 — Physical Process:** The actual physical equipment — sensors, actuators, motors, valves. The real-world process being controlled.
- **Level 1 — Basic Control:** Intelligent devices that directly control Level 0 — PLCs (Programmable Logic Controllers), RTUs (Remote Terminal Units), safety instrumented systems (SIS). They execute control logic (ladder logic, function blocks) in real-time.
- **Level 2 — Area Supervisory Control:** Local supervisory systems — HMIs (Human Machine Interfaces), SCADA servers, engineering workstations. Operators monitor and control processes from this level. Historians collect time-series data here.
- **Level 3 — Manufacturing Operations:** Plant-wide operations management — manufacturing execution systems (MES), production scheduling, batch management, historian servers. This is the boundary between OT and IT.
- **Level 4 — Business Logistics:** Enterprise IT systems — ERP (SAP, Oracle), business intelligence, email, corporate IT. Standard IT network.
- **Level 5 — Enterprise Network:** External connections — internet, cloud services, partner networks.

The model enforces that communication flows vertically (up/down adjacent levels), not horizontally (skipping levels). A Level 4 system should never directly communicate with a Level 1 system.

### OT2 — Easy
**Answer:**
IT networks manage business data — servers, workstations, email, databases. They prioritize confidentiality and integrity, use standardized hardware, and can tolerate scheduled downtime for patching. OT networks manage physical processes — PLCs, HMIs, SCADA, safety systems. They prioritize availability and safety above all else — a misapplied patch that crashes a PLC can halt production or create a safety hazard.

You can't apply standard IT patching practices to OT because: (1) many OT systems run legacy software (Windows XP, Windows 7) or embedded firmware that vendors no longer support or that hasn't been tested with patches; (2) OT systems often have 24/7 uptime requirements — a steel mill or power plant can't be shut down monthly for Patch Tuesday; (3) patching a PLC or HMI may void vendor warranties or break validated configurations; (4) the consequences of a failed patch aren't just "server is down" — it's "chemical reactor has no control" or "assembly line stopped." OT patching requires vendor coordination, extensive testing in a staging environment, and planned maintenance windows during production shutdowns.

### OT3 — Medium
**Answer:**
An Industrial DMZ (IDMZ) is a screened subnet between the IT network (Level 4/5) and the OT network (Level 0-3). It acts as a buffer zone that mediates all communication between IT and OT.

**Traffic allowed to cross (and direction):**
- IT → IDMZ: Email notifications, ERP data queries, asset management polling. But IT should never reach OT directly.
- OT → IDMZ: Historian data replication (push from OT historian to IDMZ mirror), alarm notifications, batch reports.
- IDMZ → OT: Only from specifically authorized jump hosts or data diodes. Very restricted.
- IDMZ → IT: Historian data available for business analytics, patch files available for OT systems to pull (not push).

**Allowed services in the IDMZ:** Jump host for remote access, historian mirror/data aggregator, patch management relay (WSUS/SCCM relay — OT pulls patches from here, IT pushes patches to here), firewall management, antivirus update server, OPC UA mirror server, and time server.

**Why direct Level 4 → Level 1 is dangerous:** A compromised corporate workstation (ransomware, phishing) would have a direct path to control systems. Lateral movement from IT to OT could result in manipulated PLC setpoints, disabled safety systems, or production shutdowns. The IDMZ enforces that no direct path exists — every communication must traverse a controlled, monitored, segmented boundary.

### OT4 — Medium
**Answer:**
1. **Modbus TCP:** A serial-to-TCP adaptation of the original Modbus RTU protocol (1979). Simple request-response polling. Operates at **Level 1-2** (PLC ↔ HMI/SCADA). No authentication, no encryption — entirely plaintext. Widely used because it's simple and universal, but insecure by design.

2. **OPC UA (OPC Unified Architecture):** A modern, platform-independent industrial protocol with built-in security (encryption, authentication, certificates). Supports both client-server and pub-sub models. Operates at **Level 2-3** (HMI/SCADA ↔ Historian/MES). Used for cross-vendor data exchange and increasingly for cloud connectivity.

3. **EtherNet/IP (CIP):** Uses the Common Industrial Protocol (CIP) over standard Ethernet. Allen-Bradley/Rockwell's primary protocol. Operates at **Level 1-2** (PLC ↔ I/O devices, HMI). Supports real-time control (implicit messaging) and configuration (explicit messaging).

4. **PROFINET:** Siemens' industrial Ethernet protocol. Real-time (RT) and isochronous real-time (IRT) variants for deterministic control. Operates at **Level 0-2** (field devices ↔ PLCs ↔ SCADA). Common in European manufacturing.

5. **MQTT:** A lightweight pub-sub messaging protocol over TCP. Not traditionally industrial but increasingly used for **Level 2-3** (edge gateway → cloud/historian) data transport. OPC UA PubSub can run over MQTT. Good for bandwidth-constrained or unreliable networks because of its small footprint and QoS levels.

### OT5 — Medium
**Answer:**
A **firewall** filters traffic based on rules (IP, port, protocol, stateful inspection). It allows bidirectional communication — a request passes through and the response returns. Firewalls can be misconfigured, have vulnerabilities, or be bypassed through rule manipulation.

A **hardware data diode** is a physical device that enforces unidirectional data flow at the hardware level (typically using fiber-optic hardware with a transmitter on one side and a receiver on the other — physically impossible to send data in reverse). It's not software — it's a physical constraint.

**When to use a hardware data diode:** When you need absolute assurance that data can only flow in one direction. Classic use case: OT → IT data export from a safety-critical network (e.g., nuclear power plant, water treatment) where you must guarantee that no command, malware, or data can ever flow from the IT network back to the OT network. Historian data, alarm logs, or process snapshots are pushed across the diode to a mirrored system on the IT side.

**Limitations vs firewall:** Data diodes are one-directional — no request-response patterns, no acknowledgments, no polling. This means you can only push data (OT → IT or IT → OT, but not both). They're expensive ($10K-50K+). They require custom software on both sides to handle the unidirectional protocol. Firewalls are bidirectional, cheaper, and more flexible but can be misconfigured or compromised. A data diode is the "nuclear option" when you need mathematically guaranteed isolation.

### OT6 — Medium
**Answer:**
**Data flow from SCADA to cloud analytics:**

```
PLCs/RTUs (Level 1)
    ↓ Modbus/OPC UA
SCADA/HMI (Level 2)
    ↓ OPC UA client pull
OPC UA Server (Level 2) — gateway or native SCADA OPC server
    ↓ OPC UA subscription
Edge Gateway (Level 2.5) — protocol conversion, buffering, filtering
    ↓ MQTT (TLS)
Cloud IoT Hub (Level 4/5) — AWS IoT Core / Azure IoT Hub
    ↓
Cloud Analytics Platform — time-series DB, data lake, ML pipeline
```

**With historian in the path:**
```
SCADA → Historian (Level 3) — stores high-fidelity process data
Historian → Edge Gateway (OPC UA or historian REST API)
Edge Gateway → MQTT → Cloud
```

**Security boundaries:**
- **Level 1-2 boundary:** OPC UA with certificates, or Modbus within the control zone (physically secured).
- **Level 2-3 boundary (OT to Plant Operations):** Firewall with explicit rules, OPC UA with authentication.
- **Level 3-4 boundary (IDMZ):** Data must pass through the IDMZ. The historian mirror in the IDMZ is the data aggregation point. Edge gateway connects from IDMZ.
- **IDMZ → Cloud:** Outbound-only MQTT over TLS from the edge gateway. Cloud IoT Hub has authentication (X.509 certificates on the gateway or SAS tokens). No inbound connections initiated from the internet.
- **No direct PLC → Cloud path.** Data is always mediated through a gateway that can buffer, filter, and validate.

### OT7 — Hard
**Answer:**
**IEC 62443 zones and conduits:**

A **security zone** is a logical grouping of assets (devices, systems, applications) that share the same security requirements and trust level. All assets within a zone are assumed to have the same security posture. Examples: "Control Zone" (PLCs, RTUs), "Supervisory Zone" (SCADA servers, HMIs), "Enterprise Zone" (ERP, email).

A **conduit** is a communication pathway between zones. Conduits have defined security requirements (which protocols, which direction, what filtering) and represent the trust boundaries. A conduit enforces the security policies between zones.

**Zone-and-conduit model for the manufacturing plant:**

| Zone | Assets | Security Level (SL) |
|------|--------|---------------------|
| Enterprise (Z1) | Corporate network, ERP, email | SL 1-2 |
| IDMZ (Z2) | Jump host, historian mirror, patch relay | SL 2-3 |
| Engineering (Z3) | Engineering workstations, configuration servers | SL 3 |
| Supervisory (Z4) | SCADA servers, HMIs, historian | SL 3 |
| Control (Z5) | PLCs, RTUs, drives, I/O | SL 3-4 |
| Safety (Z6) | SIS controllers, safety I/O | SL 4 (highest) |

**Conduits:**
- Z1 ↔ Z2: HTTP(S) only, outbound from Z1 to Z2 historian mirror. No direct Z1 → Z3+.
- Z2 ↔ Z3: Jump host only (SSH/RDP), MFA required, session recorded.
- Z3 ↔ Z4: Engineering protocols (OPC UA, file transfer), restricted to engineering workstations.
- Z4 ↔ Z5: Control protocols (Modbus, OPC UA, EtherNet/IP), firewall with explicit allow-list.
- Z5 ↔ Z6: Isolated or air-gapped. Only safety-rated protocols (e.g., CIP Safety, PROFIsafe). No IT traffic.

Each conduit is enforced by firewalls, ACLs, or physical separation. Security Level targets are defined per IEC 62443-3-3 based on the threat assessment (SL-T) and the system's current capabilities (SL-A).

### OT8 — Hard
**Answer:**
**Network segmentation strategy for a flat Layer 2 OT network (200 PLCs, 30 HMIs, SCADA, historian) — migrated without stopping production:**

**Phase 0: Discovery and documentation (no changes yet)**
- Deploy passive network monitoring (e.g., Nozomi, Claroty, Dragos) to map all assets, communication flows, and protocols. You can't segment what you don't understand.
- Document every PLC, HMI, IP address, MAC address, switch port, and communication path. Build an asset inventory.
- Identify critical vs non-critical systems and production line boundaries.

**Phase 1: Core switch upgrade and VLAN planning**
- Install managed Layer 3 switches at the core (if not already present).
- Design VLANs by production line and function:
  - VLAN 10: Line 1 Control (PLCs, I/O)
  - VLAN 20: Line 2 Control
  - VLAN 30: Line 3 Control
  - VLAN 40: Line 4 Control
  - VLAN 100: Supervisory (SCADA servers, historian)
  - VLAN 200: HMIs (all lines)
  - VLAN 999: Management (switches, IPMI)
- Plan firewall placement: one firewall (or pair for HA) between the supervisory VLAN and the control VLANs.

**Phase 2: Non-disruptive migration (one line at a time, during planned maintenance windows)**
- Move Line 1 PLCs to VLAN 10: reconfigure switch ports one at a time. Each PLC is moved individually — change the port VLAN, verify connectivity, move the next. Takes 15-30 minutes per PLC.
- Repeat for each line. Spread across multiple maintenance windows if needed.
- After all control VLANs are created, place the firewall between the supervisory and control zones. Start with permissive rules, monitor traffic, then tighten.

**Phase 3: Remote access and management**
- Deploy a jump host in the management VLAN with MFA (e.g., Tailscale, OpenVPN, or a dedicated OT remote access solution like Claroty SRA or Dispel).
- Vendors access via the jump host with session recording and time-limited access tokens. Never allow direct RDP/SSH from the internet to any OT system.
- Configure firewall rules: jump host → specific PLCs on specific ports only.

**Phase 4: Ongoing**
- Monitor with IDS/OT-aware anomaly detection.
- Enforce change management: no new devices without VLAN assignment and firewall rule review.

### OT9 — Hard
**Answer:**
**SIS vs BPCS:**

**BPCS (Basic Process Control System):** The "normal" control system — PLCs, DCS, HMIs that manage the process under normal operating conditions. Controls temperature, pressure, flow, level. Can be optimized for efficiency and throughput.

**SIS (Safety Instrumented System):** A separate, independent protection system that monitors the process for hazardous conditions and brings it to a safe state when dangerous conditions are detected. It only activates when the BPCS fails to maintain safe conditions. Designed per IEC 61511 (functional safety for the process industry).

**IEC 61511:** The standard for Safety Instrumented Systems in the process industry. It defines Safety Integrity Levels (SIL 1-4) based on the required risk reduction. Higher SIL = more rigorous design, testing, and redundancy requirements. SIL 4 systems (e.g., nuclear) require hardware fault tolerance, diverse redundancy, and extensive proof testing.

**Why SIS must be air-gapped or isolated:**
- The SIS must function independently of the BPCS. If they share a network, a failure or attack on the BPCS can cascade to the SIS.
- IEC 61511 and IEC 62443 require that the SIS is independent and that common-cause failures are minimized.
- If ransomware (e.g., like TRITON/TRISIS which specifically targeted SIS controllers) reaches the SIS, the attacker can disable safety functions, alter safety setpoints, or mask alarms. This means the process has no safety net — a runaway reaction, overpressure, or toxic release can occur without the SIS intervening to shut it down.

**Consequences of ransomware reaching SIS:** The attacker can disable safety functions while simultaneously manipulating the BPCS to drive the process into a hazardous state. This is the worst-case scenario in OT security — it's what TRITON attempted at a Saudi petrochemical plant in 2017. The SIS must be physically isolated (air-gapped) or at minimum connected only through a hardware data diode (one-way, SIS diagnostics only).

### OT10 — Medium
**Answer:**
**PLC (Programmable Logic Controller):** A ruggedized industrial computer that executes control logic (ladder logic, structured text, function block diagrams) in real-time. Controls individual machines or small processes. Fast scan times (1-10ms). Limited processing power. Examples: Allen-Bradley ControlLogix, Siemens S7-1500, Beckhoff CX series. Use for: individual machine control, discrete manufacturing, packaging lines.

**DCS (Distributed Control System):** An integrated control system where multiple controllers are distributed throughout the plant and coordinated by a central supervisory system. Each controller manages a section of the process. Designed for continuous process control (analog I/O, PID loops). Richer engineering tools and built-in redundancy. Examples: Honeywell Experion, Emerson DeltaV, ABB 800xA. Use for: continuous processes — refineries, chemical plants, power generation, pharmaceuticals.

**SCADA (Supervisory Control and Data Acquisition):** A system for monitoring and controlling geographically distributed assets. SCADA doesn't typically perform real-time control — it polls RTUs/PLCs, presents data on HMIs, logs data to historians, and sends setpoint changes. Designed for large-scale, distributed infrastructure. Examples: GE iFIX, Siemens WinCC, Ignition. Use for: water/wastewater, oil & gas pipelines, electrical grid, transportation.

**Can they coexist?** Yes, and they often do. A chemical plant might have a DCS for the core process, PLCs for discrete subsystems (packaging, loading), and SCADA for remote monitoring of off-site storage tanks or pipelines. They're integrated via OPC UA or protocol gateways.

### OT11 — Medium
**Answer:**
**Secure remote access architecture for OT environments:**

**Jump host (bastion):** A hardened server in the IDMZ that serves as the single point of entry for remote access. All remote users connect to the jump host first, then from there to OT systems. The jump host has MFA, session recording, and is the only system with firewall rules allowing OT access. No direct access to OT systems from the internet or corporate network.

**MFA (Multi-Factor Authentication):** Required for all remote access — at minimum TOTP (authenticator app) or hardware tokens (YubiKey). SMS-based MFA is insufficient due to SIM-swapping risk. MFA is enforced at the jump host or VPN level before any OT system is reachable.

**Session recording:** All sessions through the jump host are recorded (screen recording or command logging). This provides an audit trail for investigations and compliance. Recordings are stored in the IT/IDMZ, not in OT.

**Vendor access:** Vendors get temporary, time-limited accounts. Access is granted only during approved maintenance windows. Accounts auto-expire after the window. Vendor sessions are recorded and ideally observed (attended access) for sensitive operations. Use a privileged access management (PAM) solution for credential checkout.

**Time-limited access:** Remote access is not persistent. Users request access for a specific duration (e.g., 4-hour window). Access is automatically revoked after expiration. This prevents forgotten vendor accounts from becoming persistent attack vectors.

**Why RDP directly to an HMI from the corporate network is unacceptable:** (1) An attacker who compromises a corporate workstation (phishing, malware) gets direct access to the HMI — no segmentation boundary; (2) no MFA enforcement (HMI login is typically a local Windows password); (3) no session recording or audit trail; (4) the HMI is now exposed to all lateral movement from the IT network; (5) if the HMI is running an unpatched OS (common in OT), it's trivially exploitable. Every direct path from IT to OT is a potential attack path that bypasses the IDMZ controls.

### OT12 — Hard
**Answer:**
**Detection and response plan: nation-state compromise of vendor VPN with access to Level 3 at a water treatment facility:**

**Immediate priorities:** The water treatment process must remain safe. Operators are the first line of defense — they maintain safe operations regardless of cyber conditions.

**Detection:**
- **Network monitoring:** Deploy IDS/OT-aware anomaly detection (e.g., Nozomi, Dragos, or Zeek with ICS protocol parsers) at the Level 2-3 and IDMZ boundaries. Look for: unusual traffic patterns from the vendor VPN endpoint, connections to Level 2 or Level 1 systems that haven't been seen before, C2 beaconing, lateral movement attempts (SMB, RDP, WMI scans), protocol anomalies (Modbus commands with unusual function codes or setpoints).
- **Asset inventory:** Maintain a complete, up-to-date inventory of every device on the OT network (PLCs, HMIs, servers, switches). Unknown devices appearing on the network are immediately suspicious.
- **Log correlation:** Centralize logs from the vendor VPN appliance, firewalls, jump hosts, and any available OT system logs. Correlate vendor VPN login times with observed network activity on Level 3.

**Incident response steps:**

1. **Contain — isolate the vendor VPN immediately.** Disconnect the vendor VPN appliance from the network. If the appliance is compromised, it's the attacker's foothold. Do NOT power it off (preserve forensic evidence), but disconnect its network cable or disable its switch port.

2. **Assess — determine scope of compromise.** What systems on Level 3 has the attacker accessed? Check VPN logs, firewall logs, authentication logs on Level 3 servers. Look for: lateral movement from Level 3 to Level 2, credential theft (mimikatz, hash dumping), persistence mechanisms (scheduled tasks, services, new accounts).

3. **Contain further — isolate Level 3 from Level 2.** If there's any evidence of Level 2 access attempts, activate firewall rules to block all Level 3 → Level 2 traffic. This is a disruptive action — coordinate with the control room.

4. **Preserve evidence.** Image the compromised VPN appliance. Capture memory dumps from any accessed servers. Preserve all logs. Chain of custody for potential law enforcement involvement (nation-state attack).

5. **Eradicate.** Rebuild the VPN appliance from known-good media. Rotate all credentials that passed through the appliance. Review and reset any accounts on Level 3 systems.

**Coordination with the control room:**
- Notify the control room supervisor immediately. They must know the cyber team is responding and that certain systems may be isolated.
- The control room continues operating the plant. If Level 3 SCADA/HMI is affected, operators switch to local control (PLC panel buttons, manual operation). The plant can run on local control — it's less efficient but safe.
- Maintain constant communication between the cyber team and the control room. Any action that could affect process visibility must be coordinated.

**Role of the plant operator during a cyber incident:**
- **The operator's primary job is to keep the process safe.** They do NOT stop doing their job because of a cyber incident.
- If HMI screens go dark or show anomalous data, operators switch to reading local indicators (gauges, local displays on PLC panels) and operate in manual mode.
- Operators should NOT attempt to "fix" IT/cyber issues — that's the IR team's job.
- Operators report any unusual process behavior (valves moving unexpectedly, setpoints changing, alarms behaving strangely) to both the control room supervisor and the cyber team.
- If the process becomes unsafe (regardless of cause), operators execute the pre-defined emergency shutdown procedures. The SIS (if air-gapped and unaffected) provides the final safety layer.
