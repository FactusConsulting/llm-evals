# Cross-Domain Scenario Test Suite

**Purpose:** Evaluate model competency on realistic, multi-disciplinary problems that span infrastructure, development, and architecture.
**Scoring:** Each scenario is worth up to 6 points (3 parts x 2 points each). Use the same pass/partial/fail rubric per part.

---

## SC1 — Medium — Broken Deployments After Cluster Upgrade

Your team upgraded a production Kubernetes cluster from 1.27 to 1.29. After the upgrade, roughly 30% of pods across multiple namespaces are stuck in `CrashLoopBackOff`. The affected pods all belong to different microservices written in Go and Python. The healthy pods are running fine. You notice the failing pods all have `securityContext.runAsNonRoot: true` but no explicit `runAsUser` set, and their container images were recently rebuilt with a new base image (`cgr.dev/chainguard/static:latest`) that defaults `USER` to `root`. The cluster now enforces a `Restricted` Pod Security Standard at the namespace level, which was `Baseline` before the upgrade.

**Part A:** Explain why these pods are failing. Walk through how Kubernetes Pod Security Standards interact with `securityContext` and container image `USER` directives. What changed between `Baseline` and `Restricted` enforcement that causes this specific failure?

**Part B:** Write a Bash one-liner using `kubectl` that identifies all pods across all namespaces that are in `CrashLoopBackOff` and outputs their namespace, pod name, and the `securityContext` settings from their pod spec as a JSON object.

**Part C:** Propose a remediation strategy that fixes the immediate outage and prevents recurrence. Cover: the image-level fix, the Kubernetes manifest changes, and a CI pipeline gate that would catch this before it reaches production. How would you handle the rollout without downtime?

---

## SC2 — Hard — Cross-Region Database Failover Gone Wrong

Your company runs a primary PostgreSQL 16 instance on AWS RDS in `us-east-1` with a cross-region read replica in `eu-west-1`. During an `us-east-1` outage, your team promotes the `eu-west-1` replica to a standalone primary. Applications reconnect, but within minutes you observe: (1) writes succeed but some application queries return stale data, (2) your Terraform state still references the old RDS instance, and (3) the application's connection pooler (PgBouncer) in `eu-west-1` is reporting `server login retry` errors for 20% of connections. Latency from your US-based services to the new EU primary is 85ms.

**Part A:** Explain the stale data issue. What is the replication lag implication of promoting a cross-region read replica? How does PostgreSQL streaming replication handle WAL shipping across regions, and what data loss scenarios exist with asynchronous replication? What would you check to quantify the data loss window?

**Part B:** Your Terraform code uses the `aws_db_instance` resource with the old instance's ARN hardcoded in several places, and other resources (security groups, Route53 records, parameter groups) reference it. Describe the Terraform operations needed to import the promoted replica into state, detach the old instance, and update dependent resources without Terraform trying to destroy and recreate anything. Include specific commands.

**Part C:** Design an architecture that prevents this class of failure in the future. Cover: RDS Proxy vs PgBouncer for connection management, Route53 health checks with DNS failover, application-level retry logic, and how you would achieve RPO < 1 second across regions. Would you recommend Aurora Global Database over standard RDS, and why?

---

## SC3 — Medium — Container Image Supply Chain Compromise

Your security team's Falco deployment fires alerts at 2 AM: multiple production pods are spawning unexpected child processes (`curl`, `sh`, and an unknown binary `/tmp/.x`). The affected pods all run the same image — your internal `api-gateway:v2.4.1` — which was built and pushed to your private ECR registry 6 hours ago. The CI build log shows the image was built from a Dockerfile that pulls `node:20-slim` as the base. The Trivy scan in CI passed with zero critical CVEs. Your team suspects a compromised base image or a tampered build pipeline.

**Part A:** Outline the immediate incident response steps. How do you contain the affected pods without destroying forensic evidence? What Kubernetes and Linux commands would you use to capture the running process tree, network connections, and filesystem diff from the compromised container before killing it?

**Part B:** Write a Python or Bash script that queries your ECR registry to compare the digest of `node:20-slim` used at build time (from the CI build log) against the current upstream Docker Hub digest. The script should also extract and list all layers in your `api-gateway:v2.4.1` image and flag any layer not present in a known-good build.

**Part C:** Propose a hardened CI/CD pipeline architecture that would prevent this type of supply chain attack. Cover: image signing with Cosign/Sigstore, admission controllers (Kyverno or OPA Gatekeeper) that enforce signature verification, base image pinning by digest rather than tag, and SBOM generation. How does Notary v2 fit into this?

---

## SC4 — Hard — Migrating a Stateful Monolith to Kubernetes

Your company runs a legacy Java 11 monolith on a fleet of 8 bare-metal servers behind an F5 BIG-IP load balancer. The application stores user sessions in local memory (sticky sessions via F5), writes uploaded files to a local NFS mount (`/data/uploads`), uses an on-prem Oracle 19c database, and communicates with a mainframe via IBM MQ. Management wants this running on Kubernetes within 6 months. The app currently handles 3,000 concurrent users with 2-second p99 latency.

**Part A:** Identify the top 5 technical blockers for containerizing this application as-is and running it on Kubernetes. For each blocker, explain why it is a problem in a Kubernetes environment and propose a specific solution (e.g., what replaces sticky sessions, what replaces local NFS, how do you handle the Oracle dependency).

**Part B:** Write an OpenTofu module (HCL) that provisions the Kubernetes persistent storage layer for this migration. The module should create a StorageClass for an NFS-backed CSI driver (e.g., `nfs.csi.k8s.io`), a PersistentVolume, and a PersistentVolumeClaim. Include variables for NFS server address, export path, and storage capacity. Explain why `ReadWriteMany` access mode is necessary here.

**Part C:** Design a phased migration plan using the Strangler Fig pattern. Define at least 3 phases, what moves in each phase, and how you maintain zero-downtime during cutover. Address: how traffic is split between the legacy F5 and the new Kubernetes Ingress, how the IBM MQ integration is handled, and what rollback procedure exists if a phase fails. What metrics determine go/no-go for each phase?

---

## SC5 — Medium — Mysterious Latency Spike in Microservices

Your e-commerce platform runs 12 microservices on a Kubernetes cluster. Every day between 14:00-14:30 UTC, the `checkout-service` p99 latency spikes from 200ms to 3.5 seconds. The service is written in .NET 8 and calls `inventory-service` (Go), `payment-service` (Node.js), and `pricing-service` (Python/FastAPI) synchronously. Grafana dashboards show CPU and memory on all pods are well within limits during the spike. The Istio service mesh metrics show the latency is added between `checkout-service` and `inventory-service`. Network throughput on the nodes does not spike.

**Part A:** List a systematic debugging approach. What Istio, Kubernetes, and application-level metrics and logs would you examine? How would you use distributed tracing (Jaeger/Zipkin) to pinpoint whether the latency is in the network, the sidecar proxy, or the `inventory-service` application itself? What specific Envoy metrics would distinguish proxy-level queueing from upstream service latency?

**Part B:** After investigation, you discover the `inventory-service` runs a full inventory reconciliation job via a CronJob that hits the same database at 14:00 UTC, causing connection pool exhaustion and lock contention. The reconciliation queries hold row-level locks on the `stock_levels` table for up to 30 seconds. Write a SQL diagnostic query for PostgreSQL that shows current lock holders, waiters, and the blocking query text. Then write a Go code snippet showing how to implement a circuit breaker in the `checkout-service`'s call to `inventory-service` using a library like `sony/gobreaker`.

**Part C:** Propose an architectural solution that eliminates this class of problem entirely. Cover: separating the read path from the write/reconciliation path (CQRS), using a read replica for the reconciliation job, implementing bulkhead isolation for the database connection pool, and adjusting the CronJob scheduling. How would you use Kubernetes `PodDisruptionBudgets` and resource quotas to prevent the CronJob from starving the serving pods?

---

## SC6 — Hard — Zero-Trust Network Overhaul for a Hybrid Environment

Your organization runs workloads across an on-prem VMware vSphere cluster, two AWS accounts (production and staging), and an Azure subscription for Active Directory and Office 365 integration. Currently, the on-prem and cloud networks are connected via AWS Site-to-Site VPN (IPsec, 1 Gbps). The CISO has mandated a zero-trust architecture: no implicit trust based on network location, all service-to-service communication authenticated and encrypted, and least-privilege access for all human and machine identities. The current environment uses shared service accounts, flat network segments, and firewall rules based on IP ranges.

**Part A:** Design the identity and access layer. How would you implement machine identity for workloads across all three environments? Cover: SPIFFE/SPIRE for workload identity, integration with AWS IAM roles, Azure Managed Identities, and on-prem PKI. How do you federate identity across these environments so a workload in AWS can authenticate to a service on-prem without shared secrets?

**Part B:** Write an OpenTofu configuration that sets up the AWS networking foundation for zero-trust. Include: a Transit Gateway connecting to the VPN, VPC configurations with no public subnets, PrivateLink endpoints for AWS services (S3, RDS, ECR), and Security Groups that default-deny all traffic. Use `for_each` to create the PrivateLink endpoints from a variable list of services.

**Part C:** The VPN's 1 Gbps limit is becoming a bottleneck. Compare upgrading to AWS Direct Connect vs. adding a second VPN tunnel with ECMP vs. implementing a hybrid mesh using something like Tailscale/Netbird. Cover: cost, bandwidth, encryption, failover, and how each option fits into the zero-trust model. What changes to your routing architecture are needed for each option?

---

## SC7 — Medium — CI/CD Pipeline Causing Production Drift

Your team uses GitLab CI to deploy infrastructure with OpenTofu and applications with Helm to three environments: dev, staging, and production. Developers have noticed that production has drifted significantly from what is defined in the Git repository. An audit reveals: (1) 14 manual `tofu apply` commands were run from developer laptops in the past month, (2) the staging and production Helm values files have diverged in ways not tracked in Git, and (3) three production ConfigMaps were edited directly with `kubectl edit`. The team has no state locking, and the OpenTofu state file is stored in an S3 bucket without versioning.

**Part A:** Explain how each of the three drift sources occurred and why they are dangerous. What specific data loss or outage scenarios can result from running `tofu apply` without state locking? What happens if two engineers run `tofu apply` simultaneously on the same state file?

**Part B:** Write a GitLab CI pipeline (`.gitlab-ci.yml`) that enforces OpenTofu changes can only be applied through the pipeline. The pipeline should: run `tofu fmt -check` and `tofu validate`, run `tofu plan` and post the plan as a merge request comment, require manual approval before `tofu apply` on production, and use a DynamoDB table for state locking. Include proper use of GitLab environments and `when: manual` gates.

**Part C:** Design a drift detection and reconciliation system. Cover: how you would run scheduled `tofu plan` in CI to detect infrastructure drift, how you would use a Kubernetes admission webhook or OPA Gatekeeper policy to block direct `kubectl edit` on certain resources, and how you would structure Helm values to share a common base with per-environment overrides using Helmfile or Kustomize. What RBAC changes in both Kubernetes and AWS would enforce that only the CI service account can make changes?

---

## SC8 — Hard — Observability Stack Scaling Failure

Your observability stack consists of Prometheus (with Thanos sidecar), Loki for logs, and Tempo for traces, all running on a dedicated Kubernetes cluster. The platform serves 40 engineering teams. You have hit a wall: Prometheus is OOM-killed every 4 hours despite 64GB RAM, Loki's `ingester` pods are dropping 15% of log lines during peak hours, and Tempo queries for traces older than 2 hours time out. The Thanos compactor is 3 days behind on compaction, and the S3 bucket for long-term storage is at 14TB and growing 500GB/week. Your total metrics cardinality is 8.2 million active series.

**Part A:** Diagnose each of the four symptoms (Prometheus OOM, Loki drops, Tempo timeouts, Thanos compactor lag). For each, explain the likely root cause based on the given numbers and the architectural limitation being hit. What specific metrics or queries would you check to confirm each diagnosis? For Prometheus, explain what high cardinality means and how to identify the top offending metrics.

**Part B:** Write a Bash script that queries the Prometheus API (`/api/v1/label/__name__/values` and `/api/v1/query`) to generate a cardinality report: total number of unique metric names, the top 20 metrics by series count, and for the highest-cardinality metric, the label with the most unique values. The script should output a formatted table suitable for sharing in a Slack channel.

**Part C:** Propose a redesigned observability architecture that scales to 50 million active series and 200 teams. Cover: replacing Prometheus with a Mimir or VictoriaMetrics cluster, Loki deployment in microservices mode with separate read/write paths, Tempo with a dedicated backend (switching from local to S3-backed), and a governance model that enforces cardinality limits per team using recording rules and relabeling configs. How would you implement chargeback so teams that generate excessive telemetry bear the cost?

---

## SC9 — Medium — Securing a Public-Facing API After a Breach

A penetration test has revealed that your public REST API (running on ECS Fargate behind an ALB) is vulnerable to: (1) BOLA (Broken Object Level Authorization) — users can access other users' records by changing the ID in the URL, (2) the API returns full database objects including internal fields (`created_by_employee_id`, `internal_notes`), (3) there is no rate limiting — the tester extracted 100,000 user records in 10 minutes, and (4) API keys are passed in URL query parameters and are being logged in CloudWatch and ALB access logs. The API is a Django REST Framework application.

**Part A:** For each of the four vulnerabilities, explain the underlying security principle being violated (e.g., which OWASP API Top 10 category), the blast radius if exploited by a real attacker, and the specific code-level or infrastructure-level fix. For the BOLA issue, show a Django REST Framework code snippet implementing object-level permissions using the `get_object` method.

**Part B:** Write an OpenTofu configuration that adds a WAF (AWS WAFv2) web ACL to the ALB with rules that: rate-limit by IP to 100 requests per 5-minute window, block requests where the API key appears in the query string, apply an AWS Managed Rule Group for common attacks (SQL injection, XSS), and geo-block all countries except those your business operates in. Use a variable for the list of allowed country codes.

**Part C:** Design a defense-in-depth architecture for the API. Cover: moving API key authentication to headers and rotating all compromised keys, implementing OAuth2 with short-lived JWTs instead of API keys, adding an API gateway (Kong or AWS API Gateway) in front of the ALB for centralized auth/rate-limiting/request-transformation, enabling CloudTrail data events for API access auditing, and implementing field-level encryption for PII in the database. How do you handle the migration from API keys to OAuth2 without breaking existing consumers?

---

## SC10 — Hard — Designing a Multi-Cluster Disaster Recovery Platform

Your company is an insurance provider subject to regulatory requirements mandating RPO of 15 minutes and RTO of 1 hour for all critical systems. You need to design a platform spanning two data centers (primary in Chicago, DR in Dallas) where Kubernetes workloads can failover automatically. Current stack: 3 Kubernetes clusters (one per environment), PostgreSQL 16 with Patroni for HA, Redis Sentinel, RabbitMQ cluster, and 200TB of object storage on MinIO. All infrastructure is provisioned with OpenTofu and configured with Ansible. The network between sites is 10 Gbps dark fiber with 12ms latency.

**Part A:** Design the Kubernetes multi-cluster architecture. Compare: active-passive with Velero backup/restore vs. active-active with a service mesh (Istio multi-cluster or Cilium Cluster Mesh). For each approach, calculate whether the RPO/RTO requirements can be met given the 12ms inter-site latency and the 200TB of MinIO data. What is the replication strategy for each stateful component (PostgreSQL, Redis, RabbitMQ, MinIO)?

**Part B:** Write an Ansible playbook that configures PostgreSQL streaming replication between the primary (Chicago) and standby (Dallas) using Patroni. The playbook should: install Patroni and its dependencies, template the `patroni.yml` configuration with the correct replication settings (synchronous commit, replication slots), configure etcd as the DCS (Distributed Configuration Store), and set `synchronous_standby_names` to ensure zero data loss. Include handlers for restarting Patroni when config changes.

**Part C:** Design the automated failover orchestration. When the Chicago site goes down, what sequence of events must happen and in what order? Cover: failure detection (what monitors what, and what constitutes "site down" vs. a false positive), DNS failover (Global Server Load Balancing via GSLB or DNS), Patroni automatic promotion, Redis Sentinel failover, RabbitMQ queue mirroring and federation, MinIO site replication catch-up, and updating OpenTofu state to reflect the new primary. How do you handle split-brain scenarios? What is the procedure for failing back to Chicago once it recovers?

---

## Scoring Guide

| Rating  | Criteria                                                                 |
|---------|--------------------------------------------------------------------------|
| Pass    | Correct, complete, and demonstrates understanding                        |
| Partial | Mostly correct but missing key details or contains a minor error        |
| Fail    | Incorrect, significantly incomplete, or demonstrates misunderstanding    |

**Per part:** Pass=2, Partial=1, Fail=0 — max score per scenario is 6 (3 parts x 2 points).

| Scenario | Difficulty | Domain Focus                                     | Max Score |
|----------|------------|--------------------------------------------------|-----------|
| SC1      | Medium     | Kubernetes, Security Contexts, CI/CD             | 6         |
| SC2      | Hard       | PostgreSQL, Terraform, AWS DR                    | 6         |
| SC3      | Medium     | Container Security, Scripting, CI/CD             | 6         |
| SC4      | Hard       | Migration, OpenTofu, Architecture                | 6         |
| SC5      | Medium     | Performance, Go, PostgreSQL, Architecture        | 6         |
| SC6      | Hard       | Zero-Trust, OpenTofu, Networking                 | 6         |
| SC7      | Medium     | CI/CD, OpenTofu, Kubernetes RBAC                 | 6         |
| SC8      | Hard       | Observability, Bash Scripting, Architecture      | 6         |
| SC9      | Medium     | API Security, OpenTofu WAF, Architecture         | 6         |
| SC10     | Hard       | Multi-Cluster DR, Ansible, Architecture          | 6         |
| **Total**|            |                                                  | **60**    |
