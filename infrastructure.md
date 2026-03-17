# Infrastructure Knowledge Test Suite

**Purpose:** Evaluate model competency across networking, Linux, Kubernetes, general development, OpenTofu, and Ansible.
**Scoring:** Each question has a difficulty rating. Partial credit is fine — note what was correct vs. wrong/missing.

---

## Section 1: Networking (10 questions)

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

---

## Section 2: Linux (10 questions)

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

---

## Section 3: Kubernetes (10 questions)

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

---

## Section 4: Development (8 questions)

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

---

## Section 5: OpenTofu / Terraform (8 questions)

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

---

## Section 6: Ansible (8 questions)

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
| Networking    | 10        | 20        |
| Linux         | 10        | 20        |
| Kubernetes    | 10        | 20        |
| Development   | 8         | 16        |
| OpenTofu      | 8         | 16        |
| Ansible       | 8         | 16        |
| **Total**     | **54**    | **108**   |
