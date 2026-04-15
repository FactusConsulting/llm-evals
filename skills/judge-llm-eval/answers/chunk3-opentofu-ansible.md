# OpenTofu + Ansible Knowledge Test Suite — Answers

---

## Section 1: OpenTofu / Terraform (T1–T20)

### T1 — Easy
**Answer:**
`tofu plan` performs a dry-run: it reads current state, refreshes it against the real infrastructure, compares against the configuration, and prints the set of additions/changes/destructions that would be made. It makes no changes.

`tofu apply` executes that plan: it acquires a state lock, creates/updates/destroys resources to converge real infrastructure with the configuration, and writes the new state. Without `-auto-approve` it re-computes a plan and prompts for confirmation; `tofu apply <planfile>` applies a pre-computed plan without re-prompting.

### T2 — Easy
**Answer:**
State is OpenTofu's record of the mapping between configuration resources and real-world objects. It stores resource IDs, attribute values, dependency order, and metadata, and is the source of truth OpenTofu uses to compute diffs during plan/apply.

Remote state (stored in S3, GCS, Azure Blob, HTTP, Consul, etc.) matters because:
- It enables team collaboration — multiple engineers share a single source of truth.
- It supports state locking (e.g. via DynamoDB) to prevent concurrent applies from corrupting state.
- It keeps secrets out of local disks and Git.
- It enables CI/CD pipelines to run plans/applies against the same state.
- It can be versioned (S3 versioning) for recovery.

### T3 — Medium
**Answer:**
Both `count` and `for_each` create multiple instances of a resource, but differ in how instances are keyed:

- `count = N` creates instances keyed by integer index (`res[0]`, `res[1]`, …). Removing a middle item shifts all subsequent indices, causing OpenTofu to destroy and recreate unrelated resources.
- `for_each = toset([...])` or `for_each = { k = v }` creates instances keyed by a stable string/key (`res["web1"]`). Adding or removing items only affects that key.

`for_each` is preferred when:
- Instances have meaningful identities (names, IDs).
- The collection can change over time (items added/removed).
- You want stable addresses that don't churn on list mutation.

Use `count` only for truly homogeneous, order-insensitive replicas or for the `count = var.enabled ? 1 : 0` on/off pattern.

### T4 — Medium
**Answer:**
Manual ("out-of-band") changes are called **drift**. OpenTofu detects drift during the refresh phase of `tofu plan` (or `tofu refresh`): it reads current state, queries each resource's real attributes via its provider, and updates the in-memory state. If those refreshed attributes differ from the configuration, the plan will show changes to revert the drift back to what the configuration declares.

Handling options:
- Run `tofu apply` to revert the drift to the declared configuration.
- Update the configuration to match reality and re-apply (state is updated without changes).
- Use `lifecycle { ignore_changes = [...] }` to tell OpenTofu to ignore drift on specific attributes.
- Use `tofu import` / `import` block to bring unmanaged resources under management.
- `tofu plan -refresh-only` / `tofu apply -refresh-only` updates state to match reality without changing configuration.

### T5 — Medium
**Answer:**
```hcl
resource "aws_instance" "web" {
  for_each = toset(["web1", "web2", "web3"])

  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  tags = {
    Name = each.key
  }
}
```

### T6 — Hard
**Answer:**
The `terraform_remote_state` data source reads another root module's entire state file directly (requires read access to the remote backend) and exposes its outputs. Downsides:
- Tight coupling: consumers need credentials for the producer's backend.
- Leaks the producer's full state schema — any refactor risks breaking consumers.
- No versioning or contract; consumers break silently when outputs change.
- Must run at plan time, coupling consumer plan to producer state.

Output values themselves are just the exported surface of a module.

**Recommended alternative:** publish outputs as data through a dedicated data source that doesn't require backend access. The canonical modern pattern is:
- Store the values in a provider-native data store (AWS SSM Parameter Store, Secrets Manager, Consul KV, Vault, GCP Secret Manager) as part of the producing module's apply.
- Consumer modules read them via the provider's data source (`data "aws_ssm_parameter"`, etc.).

Why it's better: loose coupling, explicit contract (parameter names), per-consumer IAM, no cross-backend credentials, and values are queryable by any tool — not just OpenTofu.

### T7 — Hard
**Answer:**
`null_resource` provisioners run *after* the resource is "created" from OpenTofu's perspective, but provisioner output is not captured into resource attributes. If your module defines:

```hcl
output "kubeconfig" {
  value = null_resource.fetch_kubeconfig.some_attr # doesn't exist
}
```

the output is empty because the provisioner's stdout was never persisted. On first apply, dependent resources see an empty string because the output is computed before the provisioner has produced anything useful that OpenTofu can read.

**Fixes (preferred → last-resort):**
1. Stop using `null_resource + remote-exec` to generate values. Use a real data source or provider resource that actually returns the kubeconfig (`rancher2_cluster`, `rke` provider, etc.).
2. Use the `local_file`/`local_sensitive_file` + `external` data source pattern: have the provisioner write the kubeconfig to a known path, then read it with `data "local_file"` that `depends_on` the null_resource.
   ```hcl
   resource "null_resource" "fetch" {
     provisioner "remote-exec" {
       inline = ["cat /etc/rancher/rke2/rke2.yaml > /tmp/kc.yaml"]
     }
   }
   data "local_file" "kc" {
     depends_on = [null_resource.fetch]
     filename   = "/tmp/kc.yaml"
   }
   output "kubeconfig" {
     value     = data.local_file.kc.content
     sensitive = true
   }
   ```
3. Use `terraform_data` (or `null_resource`) with `triggers` and pass the result through an `external` data source that shells out and returns JSON.

Root cause: outputs that flow through provisioners need an explicit `depends_on` plus a real attribute source (a data source or `external`/`http` provider) — provisioner stdout is not an attribute.

### T8 — Medium
**Answer:**
`tofu import` brings an existing real-world object under OpenTofu management by writing its current attributes into state and associating it with a configured resource address. Syntax:

```bash
tofu import aws_instance.web i-0123456789abcdef0
```

**Limitations of the CLI command:**
- You must first hand-write a matching `resource` block — import doesn't generate configuration.
- Imports are imperative, one-off, and not tracked in code, so they're not reproducible or reviewable.
- Only one resource per invocation.
- Easy to drift between what you imported and what's in state if multiple engineers run imports.

**The `import` block (1.5+)** is declarative:
```hcl
import {
  to = aws_instance.web
  id = "i-0123456789abcdef0"
}
```
Improvements:
- Lives in code, reviewed via PR, survives in git history.
- Runs during `tofu plan`/`apply`, so imports are part of the normal workflow.
- Supports `for_each` to import many resources at once.
- Works with `tofu plan -generate-config-out=generated.tf` to auto-generate the matching `resource` block, removing the hand-write step.

### T9 — Easy
**Answer:**
A variable is a named value used in configuration.

- `variable` (input variable) is a parameter *into* a module/root — declared with `variable "name" { type = ..., default = ... }` and supplied via `-var`, `-var-file`, `TF_VAR_*`, or module arguments. It lets callers parameterise a module.
- `output` is a value *out of* a module — declared with `output "name" { value = ... }`. Child module outputs become accessible to parents as `module.<name>.<output>`; root module outputs are printed after apply and readable via `tofu output`.

Inputs flow down, outputs flow up.

### T10 — Easy
**Answer:**
A provider is a plugin that knows how to talk to a specific API (AWS, Azure, Proxmox, Kubernetes, etc.). It exposes resource types and data sources and is declared in a `required_providers` block inside `terraform { ... }` plus an optional `provider "<name>" { ... }` configuration block.

If you run `tofu plan` before `tofu init`:
- OpenTofu errors out with a message like "Missing required providers" / "Module not installed".
- `init` is what downloads provider plugins into `.terraform/`, writes/updates `.terraform.lock.hcl`, initialises the backend, and installs modules — none of which `plan` will do on its own.

### T11 — Easy
**Answer:**
`.terraform.lock.hcl` is the **dependency lock file** written/updated by `tofu init`. It pins:
- The exact provider versions selected under the `required_providers` constraints.
- Their package checksums (`h1:` hashes) for every platform seen.

Commit it to version control so that every collaborator and CI run uses the identical provider versions and verifies binary integrity, making plans/applies reproducible and protecting against supply-chain tampering. Without it, a later `init` might pick up a newer version of a provider and silently change plan output.

### T12 — Easy
**Answer:**
`tofu destroy` computes and applies a plan that deletes every resource currently tracked in state for the selected configuration. It's equivalent to `tofu apply -destroy`.

Target a single resource with `-target`:

```bash
tofu destroy -target=aws_instance.web
```

`-target` can be repeated. Targeted operations are a last-resort escape hatch — they bypass the normal dependency graph and can leave state inconsistent, so prefer refactoring configuration over habitual `-target` use.

### T13 — Easy
**Answer:**
A data source (`data "<type>" "<name>" { ... }`) reads information about an existing object without managing it. OpenTofu queries it during the refresh phase and exposes its attributes for use elsewhere in the configuration.

Use a data source instead of a managed `resource` when the object is owned by something/someone else, e.g.:

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
}
```

You're reading the AMI ID, not creating or deleting AMIs.

### T14 — Medium
**Answer:**
- `variable` blocks declare *inputs* callers can set from outside the module.
- `locals` declare internal, computed values scoped to the module; they can reference variables, resources, data sources, and other locals, and they are not settable from outside.

Use `locals` instead of input variables when:
- The value is derived from other values (e.g. `local.common_tags = merge(var.tags, { env = var.environment })`).
- You want to DRY up a repeated expression.
- The value is an implementation detail callers shouldn't override.
- You need to give a complex expression a meaningful name for readability.

Use `variable` when the caller must be able to supply or override the value.

### T15 — Medium
**Answer:**
The `lifecycle` block customises how OpenTofu manages a resource's create/update/destroy lifecycle.

```hcl
resource "aws_instance" "web" {
  # ...
  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
    ignore_changes        = [tags["LastScanned"]]
  }
}
```

- **`create_before_destroy = true`** — when a change forces replacement, OpenTofu creates the new resource first and only destroys the old one after the new is up. Use case: replacing a load-balanced EC2 instance or an auto-scaling launch template without a downtime window.
- **`prevent_destroy = true`** — any plan that would destroy this resource errors out. Use case: production RDS database or S3 bucket holding irreplaceable data — a safety net against `tofu destroy` or an accidental refactor.
- **`ignore_changes = [...]`** — drift on these attributes is ignored so OpenTofu won't try to revert them. Use case: a `tags["LastScanned"]` field mutated by an external security scanner, or `desired_capacity` on an ASG managed by an autoscaler.

### T16 — Medium
**Answer:**
A `moved` block records that a resource has been renamed or relocated in configuration, so OpenTofu updates the state address in place instead of destroying the old resource and creating a new one:

```hcl
moved {
  from = aws_instance.web
  to   = module.web.aws_instance.this
}
```

Typical uses:
- Renaming a resource (`aws_instance.foo` → `aws_instance.web`).
- Extracting resources into a new module.
- Merging two modules.
- Switching from `count` to `for_each` (paired with keyed addresses).

It replaces the old `tofu state mv` CLI dance: no manual state surgery, the refactor is tracked in code and reviewed via PR, and re-running plan after the move is a no-op.

### T17 — Hard
**Answer:**
OpenTofu builds a directed acyclic graph (DAG) of all resources, data sources, variables, outputs, and providers. During plan/apply it walks the graph, executing independent nodes in parallel (default parallelism 10, tunable via `-parallelism=N`).

- **Implicit dependencies** are inferred from expression references: when `resource B` reads `resource A`'s attribute (`aws_subnet.b.vpc_id = aws_vpc.a.id`), OpenTofu adds an edge A → B automatically. This is the preferred mechanism because it expresses real data flow.
- **Explicit dependencies** are declared via `depends_on = [aws_vpc.a]`. They add edges the graph otherwise wouldn't know about.

Effect on parallelism: every edge serialises the two endpoints. `depends_on` on a module or a frequently-referenced resource can linearise otherwise-parallel subtrees and inflate plan/apply time.

Use `depends_on` sparingly because:
- It hides intent — readers can't see the real data dependency.
- It's a blunt instrument: depending on a module means depending on *every* resource inside it.
- Real dependencies should be expressed through attribute references, which both documents the relationship and gets the ordering for free.

Reserve `depends_on` for hidden/side-effect dependencies that can't be expressed via references (e.g. IAM policy must exist before an EC2 instance profile is assumed at runtime, even though the HCL doesn't reference it).

### T18 — Hard
**Answer:**
Strategies to cut plan time on a 200+ resource codebase:

1. **Split the monolith into smaller root modules** (a.k.a. "stacks"), each with its own state. A root touching 20 resources plans in seconds. Tradeoff: you now need a way to share data between stacks (remote state or SSM/Vault), and coordinated changes span multiple applies.
2. **Use `-target` for scoped plans during development**. Tradeoff: `-target` bypasses the full graph, can mask errors in unrelated resources, and isn't safe as a default — only use while iterating.
3. **Use `-refresh=false` on iterative plans**. Skips per-resource provider API calls. Tradeoff: plan won't detect drift since the last refresh, so use for fast iteration, not CI gating.
4. **Raise `-parallelism` above the default 10** so independent branches of the graph run concurrently. Tradeoff: higher API load on providers → risk of rate limits/throttling; heavier CPU and memory use on the runner.
5. **Cache provider plugins and modules** across CI runs (`.terraform/` and the plugin cache dir via `TF_PLUGIN_CACHE_DIR`). Tradeoff: init is now fast, plan unchanged — helps the init tax, not plan itself.
6. **Prune unused data sources / providers** and collapse `for_each` over very large maps where cardinality dwarfs actual need. Tradeoff: requires auditing and may reduce generality.
7. **Replace chatty `data` lookups with locals or inputs**. Every data source is a refresh-time API call. Tradeoff: less dynamic; static values have to be updated on change.
8. **Move to a backend with partial state refresh / `-refresh-only`** and run full refreshes less often. Tradeoff: drift detection cadence drops.

In practice the biggest win is (1) — architectural decomposition. Everything else is tuning.

### T19 — Hard
**Answer:**
When a plan/apply starts, OpenTofu acquires a **lock** on the backend to prevent concurrent writes that could corrupt state:
- S3 backend locks via a DynamoDB table item (LockID).
- Azure Blob uses a blob lease.
- GCS uses object generation.
- HTTP backends define their own lock/unlock endpoints.
- Consul locks a KV key.

On success the lock is released after apply. If a CI pipeline crashes mid-apply the lock is left dangling and subsequent operations fail with `Error acquiring the state lock`.

**Manually break a lock:**
```bash
tofu force-unlock <LOCK_ID>
```
where `<LOCK_ID>` comes from the error message.

**Risks:**
- If another process is *actually still running* (e.g. apply is still mutating resources on another runner), force-unlocking lets a second apply start in parallel, which can corrupt state, duplicate resources, or cause inconsistent writes.
- Always verify the original process is really dead (CI job killed, machine offline) before force-unlocking, and in a team setting coordinate with whoever holds the lock.
- Take a state backup first (backends like S3 with versioning do this for free).

### T20 — Hard
**Answer:**
Step-by-step migration from local state to S3 + DynamoDB locking:

1. **Create the S3 bucket** (with versioning + SSE enabled) and **DynamoDB table** (primary key `LockID` of type String). These can be provisioned in a separate bootstrap stack to avoid a chicken-and-egg problem.
2. **Back up the current local state**: copy `terraform.tfstate` (and `.backup`) somewhere safe.
3. **Add the backend configuration** to the root module:
   ```hcl
   terraform {
     backend "s3" {
       bucket         = "mycorp-tofu-state"
       key            = "prod/network/terraform.tfstate"
       region         = "eu-west-1"
       dynamodb_table = "tofu-locks"
       encrypt        = true
     }
   }
   ```
4. **Run `tofu init -migrate-state`**. OpenTofu detects the backend change, prompts to copy the existing local state into the new S3 backend, and on confirmation uploads it and switches future operations to use S3. The local file is left behind but no longer consulted.
5. **Verify the migration**:
   - `tofu state list` — should match pre-migration output.
   - Check the object exists in S3 and has a version ID.
   - Run `tofu plan` — should be a no-op (no changes), proving state parity.
   - Confirm a DynamoDB lock item appears briefly while plan runs.
6. **Remove or archive** the old `terraform.tfstate`/`.backup` files from the working directory and from git (if ever committed) — state belongs only in the remote backend now.
7. Commit the backend block so collaborators pick up the new backend on their next `init`.

What happens to the existing state: `-migrate-state` copies it byte-for-byte into the configured S3 key. No resources are touched in the real world; only the location of the bookkeeping changes.

---

## Section 2: Ansible (A1–A20)

### A1 — Easy
**Answer:**
- **Task** — the smallest unit of work: a single invocation of a module against targeted hosts (e.g. "install nginx"). Tasks live inside plays or role files.
- **Playbook** — a YAML file containing one or more *plays*. A play maps a set of hosts to a list of tasks (and handlers, roles, vars). It's the top-level executable document.
- **Role** — a reusable, self-contained bundle of tasks, handlers, defaults, vars, files, templates, and meta, laid out in a standard directory structure (`tasks/main.yml`, `handlers/main.yml`, …). Playbooks include roles to compose behaviour.

Hierarchy: tasks compose into roles and plays; plays compose into playbooks.

### A2 — Easy
**Answer:**
`ansible_facts` is the dictionary of host information automatically gathered at the start of a play by the `setup` module (unless `gather_facts: false`). It includes OS, network, hardware, mounts, Python/interpreter info, etc.

Access the OS family via:

```yaml
- debug:
    msg: "OS family is {{ ansible_facts['os_family'] }}"
```

or the legacy top-level alias `{{ ansible_os_family }}` (e.g. `Debian`, `RedHat`, `Suse`).

### A3 — Medium
**Answer:**
- **`command`** — runs an executable directly via exec, no shell. No pipes, redirections, env expansion, or globbing. Safer and the default choice when you don't need shell features. Example: `command: /usr/bin/systemctl restart nginx`.
- **`shell`** — runs the command through `/bin/sh` (or configured shell), so pipes, redirections, `&&`, globs, and env vars work. Use it only when you actually need shell features. Example: `shell: "grep foo /etc/hosts | wc -l"`.
- **`raw`** — executes over the transport with no Python on the remote side and no module framework. Used to bootstrap hosts that don't have Python yet (e.g. `raw: apt-get install -y python3`) or to talk to devices that can't run Python (some network gear when no connection plugin fits).

Prefer an idempotent module over any of the three when one exists. Order of preference: real module > `command` > `shell` > `raw`.

### A4 — Medium
**Answer:**
Idempotency means running the same task repeatedly converges on the same state and only reports "changed" when it actually modified something. Most Ansible modules are written to check state first and act only if the target differs from the desired state.

**Idempotent example:**
```yaml
- name: Ensure nginx is installed
  ansible.builtin.apt:
    name: nginx
    state: present
```
Running it twice: first run installs and reports `changed`; second run sees nginx already installed and reports `ok`.

**NOT idempotent example:**
```yaml
- name: Append line to file
  ansible.builtin.shell: "echo 'hello' >> /etc/motd"
```
Every run appends another line; the file grows unboundedly and the task always reports `changed`. The idempotent equivalent is `lineinfile` or `blockinfile`:
```yaml
- ansible.builtin.lineinfile:
    path: /etc/motd
    line: hello
    state: present
```

### A5 — Medium
**Answer:**
```yaml
- name: Install htop (and epel-release on RHEL family)
  ansible.builtin.package:
    name: "{{ item }}"
    state: present
  loop: "{{ ['epel-release', 'htop'] if ansible_facts['os_family'] == 'RedHat' else ['htop'] }}"
  when: ansible_facts['os_family'] in ['Debian', 'RedHat']
```

### A6 — Hard
**Answer:**
Ansible's variable precedence (low → high, simplified and commonly cited ordering):

1. command-line values (e.g. playbook `-u` — not real vars but baseline)
2. role defaults (`roles/<role>/defaults/main.yml`) — lowest real precedence
3. inventory file or script group vars
4. inventory `group_vars/all`
5. playbook `group_vars/all`
6. inventory `group_vars/*`
7. playbook `group_vars/*`
8. inventory file or script host vars
9. inventory `host_vars/*`
10. playbook `host_vars/*`
11. host facts / cached `set_fact` from prior plays
12. play vars
13. play `vars_prompt`
14. play `vars_files`
15. role vars (`roles/<role>/vars/main.yml`) and include_vars
16. block vars (only for tasks in the block)
17. task vars (only for the task)
18. `include_params` (params on `include_*`)
19. `set_fact` / registered vars
20. role (and include_role) params
21. `include` params
22. `--extra-vars` / `-e` — highest (wins everything)

Anchor points:
- **`role defaults`** = lowest; meant to be overridden.
- **`group_vars`** and **`host_vars`** sit in the middle; host_vars beat group_vars.
- **`set_fact` / registered vars** sit near the top.
- **`extra_vars`** on the CLI always wins.

### A7 — Hard
**Answer:**
Approach: put the 3 "seed" nodes in their own inventory group, run them in a first play, then run the remaining nodes in a second play that `wait_for`s the seeds before starting.

**Inventory (`inventory.ini`):**
```ini
[rke2_seed]
node01
node02
node03

[rke2_rest]
node04
node05
# ...
node50

[rke2_agents:children]
rke2_seed
rke2_rest
```

**Playbook (`rke2-agents.yml`):**
```yaml
- name: Bring up seed RKE2 agents first
  hosts: rke2_seed
  serial: 3       # all three in lockstep, one batch
  become: true
  roles:
    - role: rke2_agent

- name: Bring up remaining RKE2 agents in batches
  hosts: rke2_rest
  serial: "20%"
  become: true
  pre_tasks:
    - name: Wait for seed nodes' RKE2 agent port to be ready
      ansible.builtin.wait_for:
        host: "{{ item }}"
        port: 9345
        timeout: 300
      loop: "{{ groups['rke2_seed'] }}"
      delegate_to: localhost
      run_once: true
  roles:
    - role: rke2_agent
```

Key points:
- **Inventory groups** (`rke2_seed`, `rke2_rest`) partition the fleet.
- **First play targets seeds only** — the second play's tasks can't run until the first play has completed on all its hosts, which is the hard barrier.
- **`serial`** controls batch size within each play; `serial: "20%"` ramps through the 47 remaining nodes in waves.
- **`wait_for`** gives a cheap runtime sanity check that the seed nodes are actually serving, instead of trusting that "finished running" means "service healthy".

### A8 — Medium
**Answer:**
`ansible-vault` is Ansible's symmetric encryption tool for secrets. It AES-encrypts files or individual values with a password (`--ask-vault-pass`, `--vault-password-file`, or per-vault-id).

**Encrypt a whole file:** `ansible-vault encrypt group_vars/prod/secrets.yml`

**Encrypt a single variable** (so the surrounding file stays cleartext and reviewable):
```bash
ansible-vault encrypt_string 'hunter2' --name 'db_password'
```

This outputs a YAML snippet like:
```yaml
db_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          66386439653236336462626566653063336164663066313232383937....
          3038633562396135646465613130373534303864373632616663663264....
```

Paste that block into your plain-text `vars.yml`. At run time Ansible decrypts just that value using the vault password, leaving the rest of the file readable by reviewers and diffable in PRs.

### A9 — Easy
**Answer:**
An inventory is the list of hosts (and groups) Ansible manages, plus any per-host/per-group variables. It can be an INI or YAML file, or a script/plugin that emits JSON.

- **Static inventory** — a file (`hosts.ini`, `inventory.yml`) you hand-edit. Simple, versionable, good for small/stable fleets.
- **Dynamic inventory** — a script or plugin that queries a source of truth (AWS EC2, Proxmox, Netbox, GCP, Kubernetes…) at run time and returns the current set of hosts and groups. Preferred when the fleet is ephemeral or externally managed, because there's no drift between reality and your inventory file.

### A10 — Easy
**Answer:**
```bash
ansible webservers -m ansible.builtin.shell -a 'df -h'
```

or with the dedicated command module:
```bash
ansible webservers -m ansible.builtin.command -a 'df -h'
```

`-i <inventory>` if not using the default, and `-b` to escalate if needed.

### A11 — Easy
**Answer:**
A handler is a special task that runs only when *notified* by another task, and only once per play (after all tasks in the play have finished, or when a `meta: flush_handlers` is hit). Typical use: restart a service after its config changes.

Trigger with `notify:`:

```yaml
tasks:
  - name: Deploy nginx config
    ansible.builtin.template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: Restart nginx

handlers:
  - name: Restart nginx
    ansible.builtin.service:
      name: nginx
      state: restarted
```

Differences from a regular task:
- Runs only when notified (regular tasks run unconditionally).
- Deduplicated: many notifications in a play → one handler run.
- Runs at the end of the play by default.
- Skipped entirely if any notifying task didn't report `changed`.

### A12 — Easy
**Answer:**
`ansible.cfg` is the configuration file for the Ansible CLI. It controls defaults for the controller process — inventory location, plugin paths, connection behaviour, output, privilege escalation, etc. Resolution order (first wins): `ANSIBLE_CONFIG` env var → `./ansible.cfg` in cwd → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg`.

Common settings:
- `inventory = ./inventory.ini`
- `remote_user = ubuntu`
- `host_key_checking = False`
- `forks = 50`
- `roles_path = ./roles:~/.ansible/roles`
- `stdout_callback = yaml`
- `pipelining = True` (under `[ssh_connection]`)
- `retry_files_enabled = False`
- `interpreter_python = auto_silent`

### A13 — Easy
**Answer:**
`register` captures a task's result (return value dict — `rc`, `stdout`, `stdout_lines`, `changed`, `failed`, module-specific keys) into a variable scoped to the current host.

```yaml
- name: Check if file exists
  ansible.builtin.stat:
    path: /etc/foo.conf
  register: foo_stat

- name: Create foo.conf if missing
  ansible.builtin.copy:
    content: "default\n"
    dest: /etc/foo.conf
  when: not foo_stat.stat.exists
```

Use `when`, `loop`, `debug`, etc., to consume the registered value in subsequent tasks.

### A14 — Medium
**Answer:**
Both pull in a separate tasks file, but differ in *when* the inclusion happens:

- **`import_tasks`** is **static** — resolved at **playbook parse time**. The imported tasks become part of the play as if written inline. Conditions/loops attached to the `import_tasks` line are copied onto each imported task; you can't loop over `import_tasks`. Tags on the import propagate to imported tasks.
- **`include_tasks`** is **dynamic** — resolved at **run time** when Ansible reaches that task. Conditions and loops on the `include_tasks` are evaluated once at that moment. You *can* loop: `include_tasks: foo.yml` with `loop:` runs the file multiple times with different vars. Tags on the include itself don't flow to imported tasks.

When to use which:
- **`import_tasks`** when the file is a fixed, unconditional block of tasks and you want straightforward tag/`--list-tasks` behaviour. Static analysis is clearer.
- **`include_tasks`** when the filename or decision to include depends on run-time variables, when you need to loop, or when the included file has dynamic conditionals that shouldn't be eagerly expanded.

Effect on conditional evaluation:
- `import_tasks` `when:` is applied to each task individually (so they're all evaluated but may all skip).
- `include_tasks` `when:` gates the *entire* include — if false, the file isn't even read.

### A15 — Medium
**Answer:**
Ansible Galaxy is the community hub and CLI for sharing and installing Ansible **roles** and **collections**. The `ansible-galaxy` CLI can install from Galaxy, git URLs, or tarballs.

A `requirements.yml` can declare both:

```yaml
---
collections:
  - name: community.general
    version: ">=8.0.0"
  - name: ansible.posix
    version: 1.5.4
  - name: https://github.com/myorg/mycoll.git
    type: git
    version: main

roles:
  - name: geerlingguy.docker
    version: 7.0.2
  - src: https://github.com/myorg/myrole.git
    scm: git
    version: v1.2.3
    name: myrole
```

Install:
```bash
ansible-galaxy install -r requirements.yml        # roles
ansible-galaxy collection install -r requirements.yml  # collections
```

Both commands are idempotent and can be pinned in CI for reproducibility. Configure install paths in `ansible.cfg` (`roles_path`, `collections_paths`) or via env vars.

### A16 — Medium
**Answer:**
Connection plugins define *how* Ansible talks to a managed node. They're selected via the `ansible_connection` var (or `connection:` on a play) and each implements `exec_command`, `put_file`, `fetch_file` against a different transport.

- **`ssh`** (default) — OpenSSH-based remote execution. Runs Python modules on the remote host. Use for Linux/Unix/macOS servers with SSH and a Python interpreter.
- **`local`** — runs commands directly on the control node itself via subprocess; no SSH. Use when a task must execute on the machine running Ansible (e.g. `hosts: localhost`, local file templating, API calls).
- **`network_cli`** (from `ansible.netcommon`) — talks to network devices over SSH but speaks a device CLI (Cisco IOS, NX-OS, Junos, Arista EOS, etc.) instead of invoking Python modules on the device. Paired with a `network_os` value and uses network-specific modules like `ios_config`.

Related plugins: `winrm`/`psrp` for Windows, `docker` / `kubectl`/`podman` for container execution, `httpapi` for REST-based network devices, `paramiko_ssh` as a pure-Python SSH alternative.

### A17 — Hard
**Answer:**
- **`delegate_to: <host>`** — runs this task on the specified host instead of the current host in the play loop. The task still has the iteration's host context (facts, vars) so you can act elsewhere using this host's data. Commonly used to hit a load balancer, a DNS API, or `localhost`.
- **`run_once: true`** — runs the task only on the first host in the current batch, not every host. Combined with `delegate_to`, the task runs a single time, targeted at a chosen host.

**Practical example:** after upgrading each app server, register it back into the load balancer from the control node using a secret known only to the LB admin:

```yaml
- name: Gather new app version from one backend
  ansible.builtin.command: /usr/local/bin/app --version
  register: app_version
  run_once: true          # only one host reports
  delegate_to: "{{ groups['app'][0] }}"  # pick a specific backend

- name: Update deployment ticket on control node
  ansible.builtin.uri:
    url: "https://tickets.internal/api/deployments"
    method: POST
    body_format: json
    body:
      service: app
      version: "{{ app_version.stdout }}"
      hosts:  "{{ groups['app'] }}"
    headers:
      Authorization: "Bearer {{ ticket_token }}"
  delegate_to: localhost
  run_once: true
```

The `uri` call executes exactly once, on the Ansible control node, but uses `app_version` that was gathered from a remote host.

### A18 — Hard
**Answer:**
Strategies for a 500-host, 30-minute playbook:

1. **Raise `forks`** from the default 5 to 50–100 in `ansible.cfg` (or `-f 50`). Controls how many hosts run in parallel.
   - Tradeoffs: more CPU/RAM on the control node, more concurrent SSH sockets, more load on shared backends (package repos, APIs). Watch control-node memory; fact gathering + templating at 500-wide can blow past limits.
2. **Enable SSH pipelining** (`[ssh_connection] pipelining = True`) so Ansible sends module code over the existing SSH session instead of writing a temp file, saving several round-trips per task. Massive win on chatty playbooks.
   - Tradeoffs: requires `requiretty` to be disabled in `/etc/sudoers` (default on modern distros). Incompatible with some legacy setups.
3. **Enable fact caching** (`fact_caching = jsonfile` or `redis`, with a TTL), so plays don't re-run `setup` on every host every run.
   - Tradeoffs: stale facts can bite if hardware/IP/OS changes between runs; you need to bust the cache (or lower TTL) around upgrades and host churn.
4. **Disable fact gathering** where not needed (`gather_facts: false`) or gather a subset (`gather_subset: !all,!any,network`). Setup is one of the slowest tasks.
   - Tradeoffs: any task that relies on `ansible_*` facts has to request them explicitly or break.
5. **Use Mitogen for Ansible** (or equivalent strategy plugin) which replaces Ansible's default fork/exec model with a persistent Python worker and router, usually cutting runtimes by 2–5×.
   - Tradeoffs: third-party, occasional compatibility issues with newer Ansible releases or exotic modules, extra install step, not always Red Hat supported.
6. **Use the `free` strategy** (`strategy: free`) so fast hosts don't wait for slow hosts at each task barrier.
   - Tradeoffs: task ordering across hosts becomes non-deterministic; handlers and `run_once` behave differently; harder to reason about.
7. **Batch with `serial`** and/or run subgroups in parallel via separate playbooks / AWX job slicing.
   - Tradeoffs: coordination complexity for a single logical change.
8. **Trim the playbook**: eliminate redundant tasks, replace shell loops with modules that do one API call, and move one-time work into `run_once` blocks.

In practice: pipelining + fact caching + forks=50 alone typically cuts wall time in half before any of the fancier changes.

### A19 — Hard
**Answer:**
Ansible uses Jinja2 for all templating (in `.j2` files and inside strings in YAML).

- **`{{ expression }}`** — *expression* delimiter. Evaluates an expression and substitutes the result into the output. Example: `{{ ansible_facts['hostname'] }}`.
- **`{% statement %}`** — *statement* delimiter. Contains control-flow keywords: `for`, `if`, `set`, `block`, `include`, `macro`, `endfor`, `endif`, … Does not emit output directly.
- **`{# comment #}`** — *comment* delimiter. Stripped from the rendered output, not visible in the final file.

**nginx upstream template (`upstream.conf.j2`):**
```jinja
{# Rendered by Ansible on {{ ansible_facts['date_time']['iso8601'] }} #}
upstream {{ upstream_name }} {
    least_conn;
{% for backend in backend_servers %}
    # {{ backend.name }} — health: {{ backend.health | default('unknown') }}
    server {{ backend.host }}:{{ backend.port | default(8080) }}{% if backend.backup | default(false) %} backup{% endif %}{% if backend.weight is defined %} weight={{ backend.weight }}{% endif %};
{% endfor %}
    keepalive 32;
}
```

Example vars:
```yaml
upstream_name: app_pool
backend_servers:
  - { name: app01, host: 10.0.0.11, port: 8080, health: green, weight: 3 }
  - { name: app02, host: 10.0.0.12, port: 8080, health: green }
  - { name: app03, host: 10.0.0.13, port: 8080, health: degraded, backup: true }
```

Renders into a valid nginx `upstream` block with per-server health comments.

### A20 — Hard
**Answer:**
Zero-downtime rolling deployment across 20 web servers with Ansible:

```yaml
- name: Rolling deploy of webapp
  hosts: webservers
  become: true
  serial: "20%"         # 4 hosts at a time
  max_fail_percentage: 10
  vars:
    app_version: "{{ lookup('env', 'APP_VERSION') }}"
    healthcheck_url: "http://{{ inventory_hostname }}:8080/health"
  pre_tasks:
    - name: Deregister host from load balancer
      ansible.builtin.uri:
        url: "https://lb.internal/api/pools/web/members/{{ inventory_hostname }}/disable"
        method: POST
        status_code: 200
      delegate_to: localhost

    - name: Wait for in-flight connections to drain
      ansible.builtin.wait_for:
        timeout: 15

  tasks:
    - name: Deploy new version (with rollback on failure)
      block:
        - name: Install new application package
          ansible.builtin.apt:
            name: "myapp={{ app_version }}"
            state: present
            update_cache: true
          notify: Restart myapp

        - name: Render new config
          ansible.builtin.template:
            src: myapp.conf.j2
            dest: /etc/myapp/myapp.conf
            mode: "0644"
          notify: Restart myapp

        - name: Flush handlers now so service restarts before we health-check
          ansible.builtin.meta: flush_handlers

        - name: Verify app health endpoint returns 200
          ansible.builtin.uri:
            url: "{{ healthcheck_url }}"
            method: GET
            status_code: 200
            return_content: true
          register: health
          retries: 10
          delay: 3
          until: health.status == 200 and (health.json.status | default('')) == 'ok'

      rescue:
        - name: Roll back to previous package version
          ansible.builtin.apt:
            name: "myapp={{ previous_app_version }}"
            state: present
            allow_downgrade: true
          notify: Restart myapp

        - name: Flush handlers after rollback
          ansible.builtin.meta: flush_handlers

        - name: Fail the play for this host after rollback
          ansible.builtin.fail:
            msg: "Deploy failed on {{ inventory_hostname }}; rolled back to {{ previous_app_version }}."

  post_tasks:
    - name: Re-register host with load balancer
      ansible.builtin.uri:
        url: "https://lb.internal/api/pools/web/members/{{ inventory_hostname }}/enable"
        method: POST
        status_code: 200
      delegate_to: localhost

    - name: Confirm host is back in rotation
      ansible.builtin.uri:
        url: "https://lb.internal/api/pools/web/members/{{ inventory_hostname }}"
        method: GET
        return_content: true
      register: lb_state
      until: lb_state.json.state == "active"
      retries: 10
      delay: 3
      delegate_to: localhost

  handlers:
    - name: Restart myapp
      ansible.builtin.service:
        name: myapp
        state: restarted
```

Key mechanics:
- **`serial: "20%"`** deploys in 4-host batches so 16/20 stay in rotation at all times.
- **`max_fail_percentage: 10`** aborts the whole play if more than 10% of a batch fails.
- **`pre_tasks`** deregister from the LB via `uri` delegated to localhost, then `wait_for` connection draining.
- **`block`/`rescue`** wraps the deploy: on any failure, `rescue` downgrades the package back to `previous_app_version` and then `fail`s so the host is clearly marked bad.
- **`uri` health check** loops with `retries/delay/until` so it waits until the app actually reports healthy rather than assuming "service restarted = healthy".
- **`post_tasks`** re-enable the host in the LB and verify it's `active` before moving on to the next batch.
