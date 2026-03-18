# Infrastructure Knowledge Test Suite

**Purpose:** Evaluate model competency across networking, Linux, Kubernetes, general development, OpenTofu, and Ansible.
**Scoring:** Each question has a difficulty rating. Partial credit is fine — note what was correct vs. wrong/missing.

---

## Section 1: Networking (20 questions)

### N1 — Easy
What is the difference between a Layer 2 switch and a Layer 3 switch?

### N2 — Easy
A host has IP `10.0.5.37/20`. What is the network address and broadcast address?

### N3 — Medium
Explain the TCP three-way handshake. What happens if the final ACK is lost?

### N4 — Medium
What is the difference between SNAT and DNAT? Give a practical example of each.

### N5 — Medium
You run `curl -v https://example.com` and get `SSL: certificate subject name does not match target host name`. List 3 possible causes.

### N6 — Medium
Explain the difference between a VLAN and a VxLAN. When would you choose VxLAN over VLAN?

### N7 — Hard
A Linux host has two NICs: `eth0` (10.0.0.5/24, default gw 10.0.0.1) and `eth1` (192.168.1.5/24). Traffic arriving on `eth1` from 192.168.1.0/24 is being replied via `eth0`. Why, and how do you fix it with policy-based routing?

### N8 — Hard
Explain how BGP path selection works. List at least 5 attributes in the correct order of preference.

### N9 — Hard
What is the MTU implication of running VxLAN over an IPsec tunnel? Show the math for the maximum inner payload if the physical MTU is 1500.

### N10 — Medium
What is the purpose of ARP, and what problem does Gratuitous ARP solve?

### N11 — Easy
What is the difference between a public IP address and a private IP address? List the three private IPv4 ranges defined in RFC 1918.

### N12 — Easy
What is DNS, and what is the difference between an A record, a CNAME record, and an AAAA record?

### N13 — Easy
What is DHCP, and what four-step process (DORA) does a client use to obtain an IP address from a DHCP server?

### N14 — Easy
What is the difference between a hub, a switch, and a router? At which OSI layer does each primarily operate?

### N15 — Easy
Explain the difference between half-duplex and full-duplex communication. Which mode do modern Ethernet links use?

### N16 — Medium
What is the purpose of the TTL field in an IP packet? How does `traceroute` exploit it to map the network path?

### N17 — Medium
Explain what a NAT gateway does. What is the difference between static NAT, dynamic NAT, and PAT (port address translation)?

### N18 — Hard
Explain how ECMP (Equal-Cost Multi-Path) routing works. What hashing strategies are commonly used, and what problems can arise with asymmetric flows when stateful firewalls are involved?

### N19 — Hard
A TCP connection between two hosts shows high latency but packet captures show no drops. The bandwidth-delay product is 10MB but the TCP window size maxes out at 64KB. Explain the problem and how TCP window scaling (RFC 1323) solves it.

### N20 — Hard
Describe how 802.1Q trunk ports work. A server with a single NIC needs to communicate on VLANs 10, 20, and 30. Explain how to configure this on Linux using sub-interfaces and what the frame format looks like on the wire.

---

## Section 2: Linux (20 questions)

### L1 — Easy
What is the difference between a hard link and a symbolic link?

### L2 — Easy
How do you find all files larger than 100MB under `/var/log`?

### L3 — Medium
A process is in state `D` (uninterruptible sleep). What does this mean, and can you kill it with `kill -9`?

### L4 — Medium
Explain the difference between `cgroups v1` and `cgroups v2`. Which does systemd prefer and why?

### L5 — Medium
What is the difference between `nftables` and `iptables`? How does the kernel handle both simultaneously?

### L6 — Medium
You run `df -h` and see a filesystem at 100%, but `du -sh /*` totals far less. What is the most likely cause?

### L7 — Hard
Explain the Linux boot process from UEFI firmware to a running systemd target. Cover: firmware → bootloader → kernel → initramfs → root → systemd.

### L8 — Hard
A server has 64GB RAM but only 2GB swap. `free -h` shows 60GB used, 1GB available, 15GB of that is `buff/cache`. The OOM killer fires. Explain why `available` can be low even with high `buff/cache`, and what kernel tunables affect this behavior.

### L9 — Medium
What does `ip netns` do, and how is it used by container runtimes?

### L10 — Medium
Explain the difference between `SIGTERM`, `SIGKILL`, and `SIGQUIT`. Which can be caught by the process?

### L11 — Easy
What is the difference between `stdout`, `stderr`, and `stdin`? How do you redirect `stderr` to a file while still displaying `stdout` on the terminal?

### L12 — Easy
What does the `chmod 755` command do? Explain what each digit represents.

### L13 — Easy
What is the difference between the `root` user and a user with `sudo` privileges?

### L14 — Easy
What is a package manager? Name the default package managers for Debian/Ubuntu and RHEL/Fedora.

### L15 — Easy
What is the `/etc/fstab` file used for? What happens if an entry is misconfigured?

### L16 — Medium
Explain what LVM (Logical Volume Manager) is. What are physical volumes, volume groups, and logical volumes, and how do you extend a logical volume on a running system?

### L17 — Hard
Explain how the Linux kernel's I/O scheduler works. Compare `mq-deadline`, `bfq`, and `none` schedulers. When would you choose each, and how do you change the scheduler for a block device at runtime?

### L18 — Hard
A system is experiencing intermittent high load averages but CPU usage is low. Explain what load average actually measures on Linux, why I/O wait can inflate it, and how you would diagnose whether the bottleneck is CPU, disk, or network using standard tools.

### L19 — Hard
Explain how SELinux enforces mandatory access control. What is the difference between `enforcing`, `permissive`, and `disabled` modes? How do you troubleshoot a daemon that fails to bind a non-standard port due to SELinux policy?

### L20 — Hard
Describe how the Linux kernel's virtual memory subsystem handles page faults. What is the difference between a minor and a major page fault? How does transparent huge pages (THP) affect application performance, and when would you disable it?

---

## Section 3: Kubernetes (20 questions)

### K1 — Easy
What is the difference between a Deployment and a StatefulSet?

### K2 — Easy
How does a Kubernetes Service of type `ClusterIP` route traffic to pods?

### K3 — Medium
Explain the difference between a `PersistentVolume`, a `PersistentVolumeClaim`, and a `StorageClass`. How do they relate?

### K4 — Medium
A pod is stuck in `CrashLoopBackOff`. Describe your troubleshooting steps (at least 4 distinct checks).

### K5 — Medium
What is the role of CoreDNS in a Kubernetes cluster? What happens to DNS resolution if the CoreDNS pods are down?

### K6 — Hard
Explain how the Kubernetes scheduler decides which node to place a pod on. Cover: filtering, scoring, and at least 3 specific factors it considers.

### K7 — Hard
You have a pod with `requests.memory: 256Mi` and `limits.memory: 512Mi`. The node has 4GB RAM with 3.5GB already requested. Will the pod be scheduled? What happens if it actually uses 600Mi at runtime?

### K8 — Hard
Explain the full lifecycle of a request hitting a Kubernetes Ingress backed by an NGINX ingress controller, all the way to the application pod. Include at least: external LB, ingress controller, Service, Endpoints, kube-proxy/iptables.

### K9 — Medium
What is a `NetworkPolicy`? If no NetworkPolicy exists in a namespace, what is the default behavior? What happens when you apply one that selects certain pods?

### K10 — Medium
Explain the difference between `RollingUpdate` and `Recreate` deployment strategies. When would you choose `Recreate`?

### K11 — Easy
What is a Kubernetes namespace, and what are the default namespaces created in a new cluster?

### K12 — Easy
What is `kubectl describe pod <name>` used for? Name at least 3 pieces of information it shows that `kubectl get pod` does not.

### K13 — Easy
What is a ConfigMap, and how can a pod consume it? Name at least two different methods.

### K14 — Easy
What is the difference between a Service of type `ClusterIP`, `NodePort`, and `LoadBalancer`?

### K15 — Easy
What is a DaemonSet, and when would you use one instead of a Deployment?

### K16 — Medium
What are taints and tolerations? How do they differ from node affinity, and give a practical use case for each?

### K17 — Medium
Explain what a Kubernetes Operator is. How does it differ from a standard controller, and what problems does the Operator pattern solve?

### K18 — Hard
Explain the etcd consistency model used by Kubernetes. What happens to the cluster if the etcd quorum is lost? How do you recover from a situation where 2 out of 3 etcd nodes are permanently lost?

### K19 — Hard
Describe how Kubernetes RBAC works. Explain the relationship between `Role`, `ClusterRole`, `RoleBinding`, and `ClusterRoleBinding`. A developer needs read-only access to pods and logs in a single namespace — write the RBAC manifests.

### K20 — Hard
You notice pod DNS resolution is slow (>5s) for external domains. Explain how `ndots` in `/etc/resolv.conf` inside a pod causes excessive DNS queries, and how you would fix it using `dnsConfig` in the pod spec.

---

## Section 4: Development (20 questions)

### D1 — Easy
What is the difference between `git rebase` and `git merge`? When should you avoid rebasing?

### D2 — Easy
Explain the difference between TCP and UDP. Name 2 protocols that use each.

### D3 — Medium
What is a race condition? Give a concrete example in any language.

### D4 — Medium
Explain the difference between symmetric and asymmetric encryption. How are both used together in TLS?

### D5 — Medium
What is a container image layer? How does layer caching affect `Dockerfile` best practices?

### D6 — Medium
You have a REST API returning HTTP 503 intermittently. Describe at least 4 things you would check, and in what order.

### D7 — Hard
Explain the CAP theorem. Give a real-world example of a system that chooses CP over AP, and one that chooses AP over CP.

### D8 — Medium
What is the difference between horizontal and vertical scaling? What architectural patterns enable horizontal scaling?

### D9 — Easy
What is an environment variable? How do you set one that persists across shell sessions on Linux?

### D10 — Easy
What is JSON, and how does it differ from YAML? Name one advantage of each format.

### D11 — Easy
What is a REST API? Explain the difference between `GET`, `POST`, `PUT`, and `DELETE` HTTP methods.

### D12 — Easy
What is version pinning in dependency management, and why is it important for reproducible builds?

### D13 — Easy
What is the difference between a compiled language and an interpreted language? Give two examples of each.

### D14 — Medium
Explain what a reverse proxy is and how it differs from a forward proxy. Name two common reverse proxy servers and a use case for each.

### D15 — Medium
What is a deadlock? What four conditions (Coffman conditions) must hold simultaneously for a deadlock to occur?

### D16 — Hard
Explain the concept of eventual consistency. How do distributed databases like Cassandra handle read-after-write consistency, and what tunable consistency levels exist?

### D17 — Hard
What is mTLS (mutual TLS)? Explain the full handshake process, including how both client and server authenticate each other. Where is mTLS commonly used in infrastructure?

### D18 — Hard
Explain how a hash table works internally, including collision resolution strategies (chaining vs. open addressing). What is the time complexity for insertion, lookup, and deletion in average and worst cases?

### D19 — Hard
What is a circuit breaker pattern in microservices? Explain its three states (closed, open, half-open) and how it prevents cascade failures. How does it relate to retry policies and exponential backoff?

### D20 — Hard
Explain the difference between optimistic and pessimistic concurrency control in databases. When would you choose each? Give a concrete example using database features (e.g., row versioning, `SELECT FOR UPDATE`).

---

## Section 5: OpenTofu / Terraform (20 questions)

### T1 — Easy
What is the difference between `tofu plan` and `tofu apply`?

### T2 — Easy
What is state in OpenTofu, and why is remote state important?

### T3 — Medium
Explain the difference between `count` and `for_each`. When is `for_each` preferred?

### T4 — Medium
What happens if you manually change a resource outside of OpenTofu (e.g., modify a VM in the cloud console)? How does OpenTofu detect and handle this?

### T5 — Medium
Write a minimal OpenTofu snippet that creates 3 identical VMs using `for_each` over a `toset(["web1", "web2", "web3"])`.

### T6 — Hard
Explain the difference between `terraform_remote_state` data source and `output` values when sharing data between root modules. What is the recommended alternative and why?

### T7 — Hard
You have a module that provisions an RKE2 cluster. The `kubeconfig` output depends on a `null_resource` with a `provisioner "remote-exec"`. The dependent resources fail because the output is empty on first apply. Explain why and how to fix it.

### T8 — Medium
What is `terraform import` (or `tofu import`), and what are its limitations? How does the `import` block (1.5+) improve on the CLI command?

### T9 — Easy
What is a variable in OpenTofu, and what is the difference between `variable` (input) and `output`?

### T10 — Easy
What is a provider in OpenTofu? What happens if you run `tofu plan` without running `tofu init` first?

### T11 — Easy
What is the `.terraform.lock.hcl` file, and why should it be committed to version control?

### T12 — Easy
What does `tofu destroy` do, and how do you target a single resource for destruction?

### T13 — Easy
What is a `data` source in OpenTofu? Give an example of when you would use one instead of a managed resource.

### T14 — Medium
Explain the difference between `locals` and `variable` blocks. When should you use `locals` instead of input variables?

### T15 — Medium
What is the `lifecycle` block in a resource? Explain the `create_before_destroy`, `prevent_destroy`, and `ignore_changes` options with a use case for each.

### T16 — Medium
What is a `moved` block in OpenTofu, and how does it help when refactoring module structure without destroying and recreating resources?

### T17 — Hard
Explain how OpenTofu's dependency graph works. What is the difference between implicit and explicit dependencies? How does `depends_on` affect parallelism, and why should it be used sparingly?

### T18 — Hard
You have an OpenTofu codebase with 200+ resources and `tofu plan` takes over 10 minutes. Identify at least 4 strategies to reduce plan time and explain the tradeoffs of each.

### T19 — Hard
Explain the OpenTofu state locking mechanism. What happens if a lock is not released (e.g., a CI pipeline crashes mid-apply)? How do you manually break a lock, and what are the risks?

### T20 — Hard
You need to migrate an existing OpenTofu project from a local state backend to an S3-compatible remote backend with state locking via DynamoDB. Describe the step-by-step process, including what happens to the existing state file and how to verify the migration succeeded.

---

## Section 6: Ansible (20 questions)

### A1 — Easy
What is the difference between an Ansible `playbook`, a `role`, and a `task`?

### A2 — Easy
What is `ansible_facts` and how do you access the OS family of a target host?

### A3 — Medium
Explain the difference between `command`, `shell`, and `raw` modules. When would you use each?

### A4 — Medium
How does Ansible handle idempotency? Give an example of a task that is idempotent and one that is NOT.

### A5 — Medium
Write an Ansible task that installs `htop` only on Debian-based systems and `epel-release` + `htop` on RedHat-based systems using a single task file.

### A6 — Hard
Explain Ansible's variable precedence order. Where do `group_vars`, `host_vars`, `extra_vars`, `role defaults`, and `set_fact` land in priority?

### A7 — Hard
You need to deploy an RKE2 agent on 50 nodes. The first 3 nodes must complete before the rest start. How do you structure this in Ansible? Cover: serial, inventory groups, and `wait_for`.

### A8 — Medium
What is `ansible-vault`? How do you encrypt a single variable inside a vars file without encrypting the entire file?

### A9 — Easy
What is an Ansible inventory file? What is the difference between a static inventory and a dynamic inventory?

### A10 — Easy
How do you run a single ad-hoc Ansible command to check disk space on all hosts in the `webservers` group?

### A11 — Easy
What is a handler in Ansible, and how does it differ from a regular task? How do you trigger a handler?

### A12 — Easy
What is the `ansible.cfg` file used for? Name at least 3 settings commonly configured there.

### A13 — Easy
What is the `register` keyword in Ansible, and how do you use the registered variable in a subsequent task?

### A14 — Medium
Explain the difference between `include_tasks` and `import_tasks`. When would you use one over the other, and how does this affect conditional evaluation?

### A15 — Medium
What is Ansible Galaxy, and how do you use a `requirements.yml` file to install roles and collections from it?

### A16 — Medium
Explain how Ansible connection plugins work. What is the difference between `ssh`, `local`, and `network_cli` connection types? When would you use each?

### A17 — Hard
Explain how Ansible's `delegate_to` and `run_once` work. Give a practical example where you need to run a task on the control node (localhost) once, using data gathered from a remote host.

### A18 — Hard
You need to manage a fleet of 500 hosts and Ansible playbook runs take over 30 minutes. Identify at least 4 strategies to improve performance and explain the tradeoffs (cover: forks, pipelining, fact caching, and mitogen or similar).

### A19 — Hard
Explain how Ansible Jinja2 templating works. What is the difference between `{{ }}`, `{% %}`, and `{# #}`? Write a template snippet that generates an nginx upstream block from a list of backend servers with health check comments.

### A20 — Hard
Describe how to implement a zero-downtime rolling deployment of a web application across 20 servers using Ansible. Cover: serial batches, pre/post tasks for load balancer registration, health checks with `uri` module, and rollback strategy on failure using `block`/`rescue`.

---

## Scoring Guide

| Rating  | Criteria                                                                 |
|---------|--------------------------------------------------------------------------|
| ✅ Pass  | Correct, complete, and demonstrates understanding                        |
| ⚠️ Partial | Mostly correct but missing key details or contains a minor error        |
| ❌ Fail  | Incorrect, significantly incomplete, or demonstrates misunderstanding    |

**Per section:** Count ✅=2, ⚠️=1, ❌=0 → max score per section is 2× question count.

| Section       | Questions | Max Score |
|---------------|-----------|-----------|
| Networking    | 20        | 40        |
| Linux         | 20        | 40        |
| Kubernetes    | 20        | 40        |
| Development   | 20        | 40        |
| OpenTofu      | 20        | 40        |
| Ansible       | 20        | 40        |
| **Total**     | **120**   | **240**   |
