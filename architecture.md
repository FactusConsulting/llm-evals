# Architecture Knowledge Test Suite

**Purpose:** Evaluate model competency across application architecture, on-premise infrastructure architecture, cloud infrastructure architecture, and OT (Operational Technology) infrastructure architecture.
**Scoring:** Each question has a difficulty rating. Partial credit is fine — note what was correct vs. wrong/missing.

---

## Section 1: Application Architecture (12 questions)

### AA1 — Easy
What is the difference between a monolith and a microservices architecture? Name 3 concrete problems that microservices introduce that monoliths don't have.

### AA2 — Easy
Explain the difference between synchronous and asynchronous communication between services. Give an example technology for each.

### AA3 — Medium
What is the difference between an API Gateway and a reverse proxy? Can an API Gateway replace a reverse proxy entirely? Why or why not?

### AA4 — Medium
Explain the Saga pattern for distributed transactions. What is the difference between choreography-based and orchestration-based sagas? When is each appropriate?

### AA5 — Medium
What is CQRS (Command Query Responsibility Segregation)? Why is it often paired with Event Sourcing? What problem does this combination solve that a traditional CRUD model doesn't?

### AA6 — Medium
Explain the Circuit Breaker pattern. What are the three states? How does it differ from a simple retry with backoff, and when would you use both together?

### AA7 — Hard
You're designing a multi-tenant SaaS platform. Compare the following tenant isolation models and their trade-offs across cost, security, operational complexity, and noisy-neighbor risk:
1. Shared database, shared schema (row-level tenant ID)
2. Shared database, separate schema per tenant
3. Separate database per tenant

### AA8 — Hard
Explain the difference between eventual consistency and strong consistency. A product team wants their inventory system to never oversell. How would you architect this — what consistency model, what data store, and what patterns would you use at scale?

### AA9 — Hard
What is a sidecar proxy in a service mesh? Explain how Envoy works in an Istio deployment. What is the data plane vs control plane? What problem does mTLS between sidecars solve that application-level TLS doesn't?

### AA10 — Medium
Explain the Strangler Fig pattern. You have a legacy .NET Framework monolith and need to incrementally migrate to .NET 8 microservices. Describe a concrete migration strategy using this pattern.

### AA11 — Medium
What is the 12-Factor App methodology? Name at least 6 factors and explain why they matter for cloud-native deployments.

### AA12 — Hard
Compare event-driven architecture using an event broker (Kafka) vs request-driven architecture using REST/gRPC. Cover: coupling, scalability, debugging complexity, ordering guarantees, and failure handling. When would you choose each?

---

## Section 2: On-Premise Infrastructure Architecture (12 questions)

### OP1 — Easy
Explain the difference between a hypervisor Type 1 (bare-metal) and Type 2 (hosted). Give 2 examples of each.

### OP2 — Easy
What is a SAN vs NAS? When would you use each? What protocols does each typically use?

### OP3 — Medium
Explain a 3-tier network architecture (core/distribution/access). Why is leaf-spine preferred in modern data centers? What problem does it solve that 3-tier doesn't?

### OP4 — Medium
You need to design a highly available Proxmox cluster with shared storage. Describe the architecture covering: node count, quorum, fencing, shared storage options (Ceph, iSCSI, NFS), and what happens during a node failure.

### OP5 — Medium
What is VLAN trunking? Explain 802.1Q tagging. A server has a single NIC but needs to be on 3 VLANs — how do you configure this on Linux?

### OP6 — Medium
Explain the difference between RAID 1, RAID 5, RAID 6, RAID 10, and RAID Z2 (ZFS). You have 6 drives and need to balance performance, capacity, and fault tolerance for a database server — which do you choose and why?

### OP7 — Hard
Design a DNS architecture for a 500-person enterprise with: internal Active Directory, a DMZ with public-facing services, split-horizon DNS, and DNSSEC on the external zone. Cover: recursive resolvers, authoritative servers, forwarders, conditional forwarding, and what happens when a laptop moves between office and VPN.

### OP8 — Hard
Explain the PKI chain of trust from root CA to end-entity certificate. You need to deploy an internal PKI for your organization. Cover: root CA (offline), subordinate/issuing CA, CRL vs OCSP, certificate templates, and auto-enrollment. What are the consequences of a compromised subordinate CA vs a compromised root CA?

### OP9 — Hard
You're consolidating 5 remote offices into a hub-and-spoke WAN. Compare: MPLS, IPsec VPN over internet, SD-WAN, and WireGuard mesh. Cover: cost, reliability, latency, management complexity, and security posture. Which would you recommend for a company with 50 users per site and latency-sensitive VoIP?

### OP10 — Medium
What is iDRAC/iLO/IPMI? Why is out-of-band management critical? What happens if your IPMI interface is exposed to the internet?

### OP11 — Medium
Explain the difference between LVM, LVM-Thin, and ZFS. When would you use each? What are the snapshot semantics for each?

### OP12 — Hard
You have a 3-node Proxmox cluster with Ceph storage and need to survive a complete site failure. Design a stretch cluster or DR strategy. Cover: Ceph CRUSH rules, monitor placement, network latency requirements, and the split-brain problem. Why is 2-site Ceph generally a bad idea without a tiebreaker?

---

## Section 3: Cloud Infrastructure Architecture (12 questions)

### CL1 — Easy
What is the difference between IaaS, PaaS, and SaaS? Give one example of each from any cloud provider.

### CL2 — Easy
Explain the Shared Responsibility Model. Where does the cloud provider's responsibility end and yours begin for: IaaS VMs, managed Kubernetes, and a SaaS product like M365?

### CL3 — Medium
Explain the difference between a VPC, a subnet, a security group, and a NACL (Network ACL). How do they layer together? What is stateful vs stateless filtering in this context?

### CL4 — Medium
You need to design a multi-account AWS/Azure strategy for a mid-size company. Explain: landing zone concept, organizational units, guardrails, shared networking (Transit Gateway / Azure Hub-and-Spoke), and centralized logging. Why is a single-account approach problematic?

### CL5 — Medium
What is Infrastructure as Code? Compare Terraform/OpenTofu, Pulumi, CloudFormation/Bicep, and Crossplane. When would you choose each?

### CL6 — Medium
Explain the difference between cloud-native autoscaling patterns: horizontal pod autoscaler (HPA), vertical pod autoscaler (VPA), cluster autoscaler, and KEDA. When would you use KEDA over HPA?

### CL7 — Hard
Design a disaster recovery strategy for a cloud-native application across two regions. Cover: RPO/RTO requirements, active-active vs active-passive, database replication (sync vs async), DNS failover (Route53/Traffic Manager), state management, and cost implications. What is the difference between a pilot light, warm standby, and multi-site active-active DR?

### CL8 — Hard
Explain the GitOps model for infrastructure and application delivery. Compare ArgoCD and FluxCD. How does GitOps handle secrets (sealed secrets, external secrets operator, Vault)? What happens when someone makes a manual change that drifts from the Git state?

### CL9 — Hard
You're migrating a stateful legacy application to Kubernetes. The app requires: local persistent storage with low latency, sticky sessions, ordered startup, and config files baked into specific filesystem paths. Design the Kubernetes architecture covering: StatefulSet, PV/PVC with local storage class, headless service, init containers, configMaps as volume mounts, and pod disruption budgets.

### CL10 — Medium
What is a service account vs a workload identity vs IRSA (IAM Roles for Service Accounts)? Why is mounting cloud provider credentials in a pod a bad practice? How does workload identity federation solve this?

### CL11 — Medium
Explain the differences between cloud object storage (S3/Blob), block storage (EBS/Managed Disk), and file storage (EFS/Azure Files). When would you use each? What are the durability and availability guarantees?

### CL12 — Hard
Design a zero-trust network architecture for a Kubernetes cluster running in the cloud. Cover: network policies, service mesh with mTLS, pod identity, admission controllers (OPA/Kyverno), image signing and verification, runtime security (Falco), and secrets management. How does this differ from a traditional perimeter-based security model?

---

## Section 4: OT Infrastructure Architecture (12 questions)

### OT1 — Easy
What is the Purdue Model (ISA-95)? Name and describe at least 4 of the levels (0-5).

### OT2 — Easy
What is the difference between IT and OT networks? Why can't you apply standard IT patching practices to OT systems?

### OT3 — Medium
Explain the role of a DMZ (IDMZ — Industrial DMZ) between IT and OT networks. What traffic should be allowed to cross, and in which direction? Why is direct connectivity from Level 4 (IT) to Level 1 (control) dangerous?

### OT4 — Medium
What are the following OT protocols, and where in the Purdue Model does each typically operate?
1. Modbus TCP
2. OPC UA
3. EtherNet/IP (CIP)
4. PROFINET
5. MQTT

### OT5 — Medium
Explain the concept of a data diode vs a firewall in OT security. When would you use a hardware data diode? What is the limitation compared to a firewall?

### OT6 — Medium
You need to collect process data from a SCADA system and push it to a cloud-based analytics platform. Design the data flow covering: historian, OPC UA server, MQTT broker, edge gateway, and cloud ingestion. Where do you place security boundaries?

### OT7 — Hard
Explain IEC 62443 (ISA/IEC 62443) security zones and conduits. How do you define a zone? What is a conduit? Design a zone-and-conduit model for a manufacturing plant with: corporate network, engineering workstations, SCADA servers, PLCs, and safety instrumented systems (SIS).

### OT8 — Hard
A manufacturing plant has 200 PLCs across 4 production lines, 30 HMIs, a SCADA system, and a historian. The plant currently has a flat Layer 2 network with no segmentation. Design a network segmentation strategy. Cover: VLAN design, firewall placement, switch architecture, remote access for vendors, and how you handle the transition without stopping production.

### OT9 — Hard
Explain the difference between Safety Instrumented Systems (SIS) and the basic process control system (BPCS). What is IEC 61511? Why must the SIS network be air-gapped or at minimum isolated from the BPCS and IT networks? What happens if a ransomware attack reaches the SIS?

### OT10 — Medium
What is the difference between a PLC, a DCS, and a SCADA system? When would you use each? Can they coexist in the same plant?

### OT11 — Medium
Explain how remote access to OT environments should be architected. Cover: jump hosts, MFA, session recording, vendor access, time-limited access, and why RDP directly to an HMI from the corporate network is unacceptable.

### OT12 — Hard
You are the OT security architect for a water treatment facility. A nation-state threat actor has compromised a vendor's VPN appliance and has access to your Level 3 network. Design your detection and response plan. Cover: network monitoring (IDS/anomaly detection), asset inventory, incident response steps, coordination with the control room, and how you ensure safe operations while isolating the threat. What is the role of the plant operator during a cyber incident?

---

## Scoring Guide

| Rating  | Criteria                                                                 |
|---------|--------------------------------------------------------------------------|
| ✅ Pass  | Correct, complete, and demonstrates understanding                        |
| ⚠️ Partial | Mostly correct but missing key details or contains a minor error        |
| ❌ Fail  | Incorrect, significantly incomplete, or demonstrates misunderstanding    |

**Per section:** Count ✅=2, ⚠️=1, ❌=0 → max score per section is 2× question count.

| Section                    | Questions | Max Score |
|----------------------------|-----------|-----------|
| Application Architecture   | 12        | 24        |
| On-Premise Infrastructure  | 12        | 24        |
| Cloud Infrastructure       | 12        | 24        |
| OT Infrastructure          | 12        | 24        |
| **Total**                  | **48**    | **96**    |
