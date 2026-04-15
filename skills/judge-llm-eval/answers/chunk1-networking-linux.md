# Networking + Linux Knowledge Test Suite — Answers

---

## Section 1: Networking (N1–N20)

### N1 — Easy
**Answer:**
A Layer 2 switch forwards Ethernet frames based on MAC addresses within a single broadcast domain/VLAN. It learns MACs by observing source addresses and builds a CAM/MAC table; it does not understand IP. A Layer 3 switch does everything a Layer 2 switch does but also performs IP routing between VLANs/subnets in hardware (ASIC), effectively combining switching and routing. L3 switches typically lack the WAN interfaces and advanced features (deep NAT, complex policy, QoS shaping) of dedicated routers but offer much higher throughput for inter-VLAN traffic.

### N2 — Easy
**Answer:**
10.0.5.37/20 has a 20-bit network mask (255.255.240.0). The third octet is masked with 11110000, so the network boundary is at multiples of 16 in the third octet. 5 falls in the 0–15 block, so:
- Network address: 10.0.0.0
- Broadcast address: 10.0.15.255
- Usable host range: 10.0.0.1 – 10.0.15.254 (4094 usable hosts)

### N3 — Medium
**Answer:**
The TCP three-way handshake establishes a connection:
1. Client sends SYN with its initial sequence number (ISN_c).
2. Server replies with SYN+ACK (its ISN_s, ack=ISN_c+1).
3. Client sends ACK (ack=ISN_s+1). Connection is now ESTABLISHED on both sides.

If the final ACK is lost, the server remains in SYN_RECEIVED and retransmits its SYN+ACK (exponential backoff, typically up to ~5–7 retries controlled by `tcp_synack_retries`). The client considers the connection ESTABLISHED and may send data; that data packet's ACK flag implicitly completes the handshake on the server side, so the connection usually recovers transparently. If neither the retransmitted SYN+ACK nor any client data arrives, the server eventually times out and drops the half-open connection.

### N4 — Medium
**Answer:**
SNAT (Source NAT) rewrites the source address (and often port) of outbound packets. Example: a home LAN with 192.168.1.0/24 behind a router that rewrites all outbound traffic to the router's single public IP so internal hosts can reach the Internet (`iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`).

DNAT (Destination NAT) rewrites the destination address/port of inbound packets, typically for port forwarding. Example: forwarding TCP port 443 on the public IP to an internal web server at 10.0.0.10:443 (`iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination 10.0.0.10:443`).

### N5 — Medium
**Answer:**
Common causes of "certificate subject name does not match target host name":
1. The server's certificate CN/SAN doesn't include the hostname you requested (e.g., cert is for `www.example.com` but you called `example.com`, or vice versa, and the SAN list is incomplete).
2. You reached the wrong server — DNS points to a different host (shared hosting default vhost, CDN catch-all, a load balancer terminating TLS with its own cert, or `/etc/hosts` pointing elsewhere).
3. SNI mismatch: the client didn't send SNI (or sent the wrong name), so the server returned its default certificate instead of the correct virtual-host cert.

### N6 — Medium
**Answer:**
A VLAN (802.1Q) is a Layer 2 segmentation mechanism that tags Ethernet frames with a 12-bit VLAN ID, allowing up to 4094 usable VLANs on a single physical L2 network. VxLAN is a Layer 2 overlay encapsulated in UDP (port 4789) over an IP/Layer 3 underlay, using a 24-bit VNI that allows ~16 million segments.

Choose VxLAN when: you need more than 4094 segments (large multi-tenant clouds), you must stretch L2 across L3 boundaries (different datacenters, routed spine-leaf fabrics), or you want to decouple tenant topology from the physical network and avoid MAC address table explosion on core switches.

### N7 — Hard
**Answer:**
Linux's default FIB uses only the destination address for route lookup. A reply to a packet received on eth1 will be routed via the system's default gateway (10.0.0.1 on eth0) unless the destination is in eth1's directly connected 192.168.1.0/24. If the client is on 192.168.1.0/24 the reply goes out eth1; but if the source was from beyond eth1 (or asymmetric routing tests fail due to rp_filter), reverse-path filtering can also drop packets. The root cause of "reply via eth0" is usually that Linux picks the default route regardless of ingress interface.

Fix with policy-based routing: create a second routing table for eth1 and a rule that forces traffic sourced from 192.168.1.5 (or arriving for that subnet) to use it:

```
echo "200 eth1tbl" >> /etc/iproute2/rt_tables
ip route add 192.168.1.0/24 dev eth1 src 192.168.1.5 table eth1tbl
ip route add default via 192.168.1.1 dev eth1 table eth1tbl
ip rule add from 192.168.1.5 table eth1tbl
```

Also set `net.ipv4.conf.eth1.rp_filter=2` (loose) to prevent reverse-path drops. Now replies from eth1's address are routed out eth1.

### N8 — Hard
**Answer:**
BGP selects the best path per prefix by walking a deterministic list of attributes. A standard order (Cisco-style, widely mirrored by other vendors):
1. **Weight** (Cisco-proprietary, highest wins, local to router)
2. **LOCAL_PREF** (highest wins, propagated within AS)
3. **Locally originated** (network/aggregate/redistributed prefers local)
4. **AS_PATH length** (shortest wins)
5. **Origin type** (IGP < EGP < Incomplete)
6. **MED / Multi-Exit-Discriminator** (lowest wins)
7. **eBGP over iBGP**
8. **Lowest IGP metric to next-hop**
9. **Oldest route** (eBGP stability)
10. **Lowest BGP router ID**
11. **Lowest neighbor IP address**

### N9 — Hard
**Answer:**
VxLAN adds 50 bytes of overhead over IPv4 (14 outer Ethernet + 20 outer IP + 8 UDP + 8 VxLAN = 50). IPsec ESP in tunnel mode with AES-CBC + HMAC-SHA adds roughly 20 (new IP) + 8 (ESP header) + 16 (IV) + up to 15 (padding) + 2 (pad len/next hdr) + 12 (ICV) ≈ 73 bytes of overhead (worst case, often cited as ~56–73 depending on cipher/auth).

Using conservative figures: 1500 (physical MTU) − 73 (IPsec) − 50 (VxLAN) = **1377 bytes** max inner L2 frame. Subtract 14 bytes for the inner Ethernet header to get a **1363-byte inner IP MTU**, and a **1323-byte TCP MSS** (minus 40 for inner IPv4+TCP headers). In practice operators round down further (e.g. MTU 1350) to accommodate varying cipher overheads and any additional encapsulation.

### N10 — Medium
**Answer:**
ARP (Address Resolution Protocol) maps IPv4 addresses to MAC addresses on a local L2 segment. When a host needs to send to an IP on its subnet, it broadcasts "who has 10.0.0.5?"; the owner replies unicast with its MAC, and the sender caches it.

Gratuitous ARP is an ARP request/reply a host sends for its *own* IP, unsolicited. It solves two problems: (1) **duplicate address detection** — if anyone else replies, you know the IP is already taken; and (2) **cache refresh / failover** — it forces neighbors and switches to update their ARP and MAC tables immediately, which is essential when an IP moves to a new MAC (VRRP/keepalived failover, VM live migration, interface bonding switchover) so traffic doesn't blackhole until stale entries age out.

### N11 — Easy
**Answer:**
A public IP is globally routable on the Internet and must be unique. A private IP is only valid inside a private network and is not routed on the public Internet; it needs NAT to reach the Internet. The three RFC 1918 ranges are:
- 10.0.0.0/8 (10.0.0.0 – 10.255.255.255)
- 172.16.0.0/12 (172.16.0.0 – 172.31.255.255)
- 192.168.0.0/16 (192.168.0.0 – 192.168.255.255)

### N12 — Easy
**Answer:**
DNS (Domain Name System) is a distributed hierarchical database that maps human-readable names to IP addresses (and other records). Record types:
- **A record** — maps a name to an IPv4 address.
- **AAAA record** — maps a name to an IPv6 address.
- **CNAME record** — an alias that maps one name to another name (which is then resolved further). CNAMEs cannot coexist with other records at the same name and cannot be used at a zone apex in classic DNS.

### N13 — Easy
**Answer:**
DHCP (Dynamic Host Configuration Protocol) automatically assigns IP configuration (address, netmask, gateway, DNS, lease time) to clients. The DORA exchange:
1. **Discover** — client broadcasts DHCPDISCOVER looking for any server.
2. **Offer** — one or more servers reply with DHCPOFFER containing an available address.
3. **Request** — client broadcasts DHCPREQUEST accepting one offer (identifying the chosen server).
4. **Acknowledge** — chosen server replies with DHCPACK confirming the lease; client configures its interface.

### N14 — Easy
**Answer:**
- **Hub**: dumb repeater; forwards every incoming bit to all other ports; one collision domain. Layer 1 (physical).
- **Switch**: learns MAC addresses, forwards frames only out the port where the destination lives; each port is its own collision domain. Layer 2 (data link).
- **Router**: forwards packets between different IP networks based on a routing table; separates broadcast domains. Layer 3 (network).

### N15 — Easy
**Answer:**
Half-duplex allows communication in both directions but only one at a time; collisions are possible and CSMA/CD is required (classic shared-hub Ethernet). Full-duplex allows simultaneous transmit and receive on separate channels/pairs; no collisions. Modern switched Ethernet links (10/100/1000/10G and beyond) operate full-duplex by default; half-duplex only survives on legacy hubs or misnegotiated links.

### N16 — Medium
**Answer:**
TTL (Time To Live) is an 8-bit field in the IPv4 header that limits a packet's lifetime. Each router that forwards the packet decrements TTL by 1; if TTL reaches 0, the router drops the packet and sends an ICMP "Time Exceeded" back to the source. This prevents packets looping forever.

traceroute exploits this by sending probes (UDP, ICMP, or TCP depending on implementation) with TTL=1, then TTL=2, then TTL=3, and so on. Router 1 drops the TTL=1 packet and returns ICMP Time Exceeded, revealing its IP. Router 2 responds to the TTL=2 packet, and so forth, until the destination is reached (it replies with the normal service reply or ICMP Port Unreachable). The ordered list of responders is the path.

### N17 — Medium
**Answer:**
A NAT gateway rewrites addresses/ports in IP headers as packets cross it, allowing hosts on one side to communicate using addresses that aren't valid on the other (typically private → public).
- **Static NAT**: fixed one-to-one mapping between an internal and an external address. Always the same both directions.
- **Dynamic NAT**: pool of external addresses; internal hosts get mapped to whichever external address is free, for the duration of the session. Still one-to-one while active, but not fixed.
- **PAT (Port Address Translation) / NAPT / "overload"**: many internal hosts share a single external address, disambiguated by rewriting the source port. This is what home routers and cloud NAT gateways typically do.

### N18 — Hard
**Answer:**
ECMP installs multiple equal-cost next-hops for the same prefix and distributes flows across them. To keep a flow on one path (avoiding reordering), routers hash a tuple and pick a next-hop by `hash % N`. Common hash inputs:
- L3 hash: src IP, dst IP (and sometimes protocol).
- L4 hash: 5-tuple (src IP, dst IP, protocol, src port, dst port) — default on most modern gear.
- Some hardware also hashes the IPv6 flow label or MPLS entropy label.

Problems with stateful firewalls and asymmetric flows: if forward and reverse directions hash to different paths, and each path traverses a different stateful firewall (or a different member of a firewall cluster), the return packet hits a firewall that never saw the SYN and gets dropped. Also, if a next-hop is added/removed, naïve modulo hashing rebalances every flow (mitigated by consistent hashing / resilient hashing). Fixes: symmetric hashing (sort the tuple so both directions produce the same hash), state sync between firewalls, or steering flows via a single firewall pair.

### N19 — Hard
**Answer:**
The TCP receive window field in the header is 16 bits, so the advertised window maxes out at 65,535 bytes (~64 KB). With a bandwidth-delay product of 10 MB, the sender can have at most 64 KB in flight before it must stop and wait for ACKs — throughput is capped at `window / RTT` regardless of available bandwidth. That's the "long fat pipe" problem.

RFC 1323 (now RFC 7323) defines the **Window Scale** TCP option, negotiated in the SYN/SYN-ACK. It carries a shift count (0–14); the effective window is `advertised_window << shift`, allowing windows up to 2^30 = 1 GB. With a shift of 8, a 64 KB field advertises 16 MB, large enough to fill a 10 MB BDP pipe. Both endpoints must support and enable it (`net.ipv4.tcp_window_scaling=1` on Linux, which is the default). The option also defines TCP timestamps used by PAWS (protection against wrapped sequence numbers), which is required once windows can exceed 2^31.

### N20 — Hard
**Answer:**
802.1Q "trunk" ports carry frames for multiple VLANs by inserting a 4-byte tag between the Ethernet source MAC and the EtherType. The tag contains a 16-bit TPID (0x8100), 3 bits PCP (QoS), 1 bit DEI, and 12 bits VLAN ID (1–4094 usable). An untagged "native" VLAN may also pass on the same link.

On Linux, create VLAN sub-interfaces on a single NIC:

```
ip link add link eth0 name eth0.10 type vlan id 10
ip link add link eth0 name eth0.20 type vlan id 20
ip link add link eth0 name eth0.30 type vlan id 30
ip addr add 10.10.0.5/24 dev eth0.10
ip addr add 10.20.0.5/24 dev eth0.20
ip addr add 10.30.0.5/24 dev eth0.30
ip link set eth0 up && ip link set eth0.10 up && ip link set eth0.20 up && ip link set eth0.30 up
```

(or equivalent in netplan/NetworkManager/ifupdown). The switch port must be configured as a trunk allowing VLANs 10, 20, 30.

On the wire a tagged frame looks like: `[Dst MAC (6)][Src MAC (6)][TPID 0x8100 (2)][PCP/DEI/VID (2)][EtherType (2)][Payload][FCS (4)]`. The VLAN tag adds 4 bytes, pushing max frame size from 1518 to 1522 bytes (switches must accept "baby giants").

---

## Section 2: Linux (L1–L20)

### L1 — Easy
**Answer:**
A **hard link** is an additional directory entry pointing at the same inode as the original file. Both names are equal peers; the file's data is freed only when the last link is removed. Hard links cannot cross filesystems and (on most filesystems) cannot target directories.

A **symbolic link (symlink)** is a small special file whose contents are a path to another file. It has its own inode, can cross filesystems, can point to directories, and becomes a "dangling" link if the target is removed or moved.

### L2 — Easy
**Answer:**
```
find /var/log -type f -size +100M
```
(Use `-size +100M` for files strictly larger than 100 MiB. Add `-exec ls -lh {} +` or `-printf '%s %p\n'` to see sizes.)

### L3 — Medium
**Answer:**
State D means the process is in **uninterruptible sleep**, usually waiting on a kernel operation that cannot be safely interrupted — almost always synchronous I/O (disk, NFS, device driver). In this state the process does not receive signals, so `kill -9` (SIGKILL) is queued but not delivered until the kernel call returns. If the underlying operation never completes (e.g., dead NFS server, broken hardware), the process stays D forever and no signal, not even SIGKILL, can remove it; the only remedies are fixing the underlying I/O (reconnecting the NFS mount, resetting the device) or rebooting.

### L4 — Medium
**Answer:**
**cgroups v1** exposes each controller (cpu, memory, blkio, pids, …) as its own separate hierarchy mounted under `/sys/fs/cgroup/<controller>`. A process can live in a different cgroup per controller, which makes policy composition messy and creates well-known problems (e.g., the memory/blkio write-back accounting split).

**cgroups v2** uses a single unified hierarchy: every process is in exactly one cgroup, and all controllers are enabled on that cgroup via `cgroup.subtree_control`. It has cleaner delegation semantics, a consistent interface file format, better PSI/pressure metrics, and improved I/O + memory accounting.

systemd prefers cgroups v2 (and on modern distros defaults to it) because the unified hierarchy matches systemd's unit/slice model exactly, simplifies resource delegation to user sessions and containers, and provides the richer accounting/PSI interfaces systemd-oomd relies on.

### L5 — Medium
**Answer:**
iptables uses the legacy xtables kernel interface and a separate binary/table per protocol family (iptables, ip6tables, arptables, ebtables). nftables replaces all of those with a single kernel subsystem (`nf_tables`) and one userspace tool (`nft`) using a unified, scriptable syntax; it supports atomic rule replacement, sets/maps, and compiled rulesets that are much faster for large rule counts.

Both can coexist because the kernel provides compatibility via `iptables-nft` (an iptables-syntax frontend that actually programs nftables) and because classic `iptables-legacy` and `nftables` use different Netfilter hooks that run in a defined order. In practice you should use only one implementation at a time; mixing `iptables-legacy` and `nft` on the same host is supported but confusing, because rules in each are evaluated independently in their respective chains and the first to drop/accept wins.

### L6 — Medium
**Answer:**
The most likely cause is that a process still holds an open file descriptor on a file that has been unlinked (deleted). The directory entry is gone so `du` can't see it, but the inode and its blocks are kept until the last fd is closed, so `df` still counts them. Find the culprit with:

```
lsof +L1            # lists open files with link count 0
lsof / | grep deleted
```

Restarting (or HUPing) the holding process releases the space. Other possibilities: reserved blocks for root (`tune2fs -m`), a filesystem mounted *over* a populated directory hiding files, or sparse/quota issues — but the deleted-file-still-open case is by far the most common.

### L7 — Hard
**Answer:**
1. **UEFI firmware** runs POST, initializes hardware, reads boot entries from NVRAM, and loads the configured EFI application from the EFI System Partition (ESP) — typically `\EFI\<distro>\shimx64.efi` or `grubx64.efi`. Secure Boot validates signatures along the way.
2. **Bootloader** (GRUB2, systemd-boot, rEFInd). It reads its config, presents a menu, then loads the Linux kernel (`vmlinuz`) and initramfs into memory and hands off control with a kernel command line.
3. **Kernel** decompresses itself, initializes core subsystems (memory, scheduler, drivers built in), mounts the initramfs as a temporary rootfs, and executes `/init` inside it.
4. **initramfs** is a cpio archive containing the modules and tools needed to find and mount the *real* root filesystem — e.g., loading storage drivers, assembling MD/LVM/LUKS volumes, waiting for the root device, running fsck. It then `switch_root`s to the real root.
5. **Real root** is mounted read-write (or initially ro then remounted), and the kernel executes `/sbin/init`, which on modern distros is a symlink to `/lib/systemd/systemd` (PID 1).
6. **systemd** reads `/etc/systemd/system/default.target` (usually `graphical.target` or `multi-user.target`), resolves its dependency graph, and starts units in parallel until the target is reached. The system is then "up".

### L8 — Hard
**Answer:**
`MemAvailable` is the kernel's estimate of how much memory a new workload could get *without* swapping, and it is **not** simply `free + buff/cache`. The kernel subtracts cache pages that can't be cheaply reclaimed: the low watermark reserve, mlocked pages, tmpfs/shmem, dirty pages that must first be written back, kernel slab that isn't reclaimable (SUnreclaim), hugepages, and pinned pages (e.g., by DMA/RDMA, GPUs, io_uring). So a box with 15 GB of buff/cache may only show 1 GB available if most of that cache is shmem/tmpfs, mlocked, or dirty, and the OOM killer will fire well before swap fills.

Relevant tunables:
- `vm.swappiness` — bias between reclaiming anon vs. file pages.
- `vm.vfs_cache_pressure` — how aggressively to reclaim dentry/inode caches.
- `vm.min_free_kbytes` / watermark_scale_factor — reserved free memory, raises the OOM threshold.
- `vm.dirty_ratio` / `vm.dirty_background_ratio` — how much dirty cache can accumulate before writeback.
- `vm.overcommit_memory` / `vm.overcommit_ratio` — commit accounting.
- `vm.oom_kill_allocating_task`, `/proc/<pid>/oom_score_adj` — OOM killer behavior.
Inspect `/proc/meminfo` (Shmem, SReclaimable, SUnreclaim, Mlocked, Dirty, Writeback) to see *why* available is low.

### L9 — Medium
**Answer:**
`ip netns` manages **network namespaces**, a kernel feature that gives a process its own isolated network stack: separate interfaces, routing tables, iptables/nftables rules, sockets, and /proc/net. Commands: `ip netns add foo`, `ip netns exec foo <cmd>`, `ip link set veth0 netns foo`.

Container runtimes (Docker, containerd, CRI-O, podman, Kubernetes via CNI) use net namespaces as the primary network isolation primitive. When a container starts, the runtime creates a new netns, moves one end of a veth pair into it, configures an address and routes, and then starts the container process inside that namespace. CNI plugins (bridge, macvlan, calico, cilium, flannel) do exactly this plumbing. `ip netns` exposes the same mechanism manually and is great for testing CNI-like setups.

### L10 — Medium
**Answer:**
- **SIGTERM (15)** — polite "please terminate" request. Can be caught, handled, or ignored; the process is expected to clean up and exit. Default action: terminate. This is the default signal sent by `kill` and systemd's stop.
- **SIGKILL (9)** — forceful, unconditional termination by the kernel. **Cannot be caught, blocked, or ignored.** The process is killed immediately with no cleanup.
- **SIGQUIT (3)** — similar to SIGTERM but the default action is to terminate **and produce a core dump**. Can be caught, blocked, or ignored. Often sent via Ctrl-\\ on a terminal.

So SIGTERM and SIGQUIT can be caught; SIGKILL cannot. (SIGSTOP is the other uncatchable one.)

### L11 — Easy
**Answer:**
Every process starts with three standard file descriptors:
- **stdin (fd 0)** — input, by default the terminal keyboard.
- **stdout (fd 1)** — normal output, by default the terminal.
- **stderr (fd 2)** — error/diagnostic output, by default also the terminal but a separate stream.

To redirect stderr to a file while stdout keeps going to the terminal:
```
command 2> errors.log
```
(Or `command 2>>errors.log` to append. To capture both, `command >out.log 2>&1`; to swap them, `command 3>&1 1>&2 2>&3`.)

### L12 — Easy
**Answer:**
`chmod 755 file` sets the permission bits to `rwxr-xr-x`. The three octal digits are owner / group / others, each a sum of read(4) + write(2) + execute(1):
- 7 = 4+2+1 = rwx for owner
- 5 = 4+0+1 = r-x for group
- 5 = 4+0+1 = r-x for others

Result: owner can read/write/execute; group and others can read and execute but not write. Common for executables and directories that should be world-traversable.

### L13 — Easy
**Answer:**
**root** is UID 0, the superuser — the kernel bypasses permission checks for UID 0 (with a few caveats like immutable flags and MAC systems). A user with **sudo** is a normal unprivileged user whose account is listed in `/etc/sudoers` (or a drop-in) as allowed to run specific commands as root (or as another user) after authenticating with their own password. sudo provides auditable, per-command, policy-controlled privilege escalation, whereas being root means unrestricted access at all times. You should never log in as root directly on production systems; use sudo so every privileged action is attributable and logged.

### L14 — Easy
**Answer:**
A package manager installs, upgrades, removes, and tracks software packages along with their dependencies, using a central repository of signed metadata. Defaults:
- **Debian/Ubuntu**: `dpkg` is the low-level tool; `apt` (and `apt-get`/`aptitude`) is the high-level dependency-resolving front end.
- **RHEL/Fedora/CentOS**: `rpm` is the low-level tool; `dnf` is the modern high-level front end (replacing `yum`, which is still a compatible alias).

### L15 — Easy
**Answer:**
`/etc/fstab` is the filesystem table — it lists filesystems the system should know about, with six fields per line: device (or UUID/LABEL), mount point, filesystem type, mount options, dump flag, and fsck pass. systemd-fstab-generator (or classic `mount -a`) reads it at boot to mount everything.

If an entry is misconfigured: a bad option or missing device may cause `mount` to fail, and on a traditional boot the system drops to emergency/rescue mode asking for the root password. Under systemd, units with `nofail` will be skipped; without `nofail`, boot hangs on the dependency and eventually times out into emergency mode. Common fixes: boot from rescue media and edit fstab, or add `nofail,x-systemd.device-timeout=10s` to non-critical mounts.

### L16 — Medium
**Answer:**
LVM sits between block devices and filesystems and provides flexible volume management.
- **Physical Volume (PV)** — a raw block device (whole disk or partition) initialized for LVM with `pvcreate`.
- **Volume Group (VG)** — a pool formed by one or more PVs (`vgcreate vg0 /dev/sda2 /dev/sdb1`). It's the allocation unit for space.
- **Logical Volume (LV)** — a "virtual partition" carved from a VG (`lvcreate -L 20G -n data vg0`), exposed as `/dev/vg0/data`, on top of which you create a filesystem.

To extend an LV and its filesystem online:
```
# optionally first: add more space to the VG
pvcreate /dev/sdc1
vgextend vg0 /dev/sdc1

lvextend -L +10G /dev/vg0/data          # or -l +100%FREE
resize2fs /dev/vg0/data                 # ext4
# or: xfs_growfs /mountpoint            # XFS (must be mounted)
```
`lvextend --resizefs` combines the last two steps.

### L17 — Hard
**Answer:**
The block layer schedules I/O requests between the filesystem and the device driver, merging adjacent requests and reordering to optimize throughput/latency. Modern Linux uses the multi-queue (`blk-mq`) framework; the schedulers are:

- **none** (noop for mq): no reordering beyond basic merging. Best for fast devices where the device/firmware already handles ordering — NVMe SSDs, hardware RAID with large caches — and for virtual guests where the host reschedules anyway.
- **mq-deadline**: imposes per-request deadlines (separate read/write queues, reads prioritized) to bound worst-case latency. Good general-purpose choice for SATA SSDs and rotational disks where you want predictable latency without the overhead of BFQ.
- **bfq (Budget Fair Queueing)**: proportional-share scheduler that gives each process/cgroup a fair budget and strongly favors interactive workloads. Best on desktops or rotational disks with competing workloads; has higher CPU overhead, usually not chosen for high-IOPS NVMe servers.

Change at runtime:
```
cat /sys/block/nvme0n1/queue/scheduler     # shows available, current in [brackets]
echo mq-deadline > /sys/block/nvme0n1/queue/scheduler
```
Persist via a udev rule (`/etc/udev/rules.d/60-ioschedulers.rules`).

### L18 — Hard
**Answer:**
On Linux, load average is the exponentially smoothed (1/5/15-minute) count of tasks that are **runnable OR in uninterruptible sleep (state D)**. Unlike traditional Unix, which only counted runnable, Linux includes D-state so that heavy disk/NFS waits also push the load up. That is why high load can coexist with low CPU usage: the box is mostly blocked on I/O.

Diagnosis tools:
- **CPU**: `top`/`htop`, `mpstat -P ALL 1`, `vmstat 1` (columns `r` runnable, `us/sy/id` cpu), `pidstat -u 1`.
- **I/O wait**: `vmstat 1` (`wa`, `b` blocked tasks), `iostat -xz 1` (`%util`, `await`, `r/s`, `w/s`, queue depth), `iotop`, `pidstat -d 1`, `biolatency`/`biosnoop` (bcc).
- **What is each process doing**: `ps -eo pid,stat,wchan,comm` to see D-state tasks and the kernel function they're blocked in.
- **Network**: `ss -s`, `ss -tinp`, `nstat`, `sar -n DEV 1`, `iftop`, `tcpdump`; retransmits and high `Retrans` in `ss -ti` indicate network issues.
- **Pressure (cgroups v2)**: `/proc/pressure/{cpu,io,memory}` — PSI directly reports how much time tasks stalled on each resource, which is the cleanest way to attribute the bottleneck.

### L19 — Hard
**Answer:**
SELinux enforces Mandatory Access Control by labeling every process (a *domain*) and every object (file, port, socket — a *type*) with a security context and consulting a compiled policy on every access. Even root is constrained by the policy; DAC permissions must allow the access first, then SELinux decides whether the policy also allows it. This is called type enforcement (plus RBAC and MLS in stricter policies).

Modes (set via `setenforce`, `getenforce`, `/etc/selinux/config`):
- **enforcing** — policy is applied and violations are blocked and logged.
- **permissive** — policy is *not* applied but violations are still logged (AVCs). Used for debugging.
- **disabled** — SELinux is not loaded at all. Requires a reboot to re-enable properly.

Troubleshooting a daemon that cannot bind a non-standard port:
1. Check audit log: `ausearch -m AVC -ts recent` or `journalctl -t setroubleshoot`. Expect an AVC like `name_bind` denied for the service type on a port of type `unreserved_port_t`.
2. `semanage port -l | grep <service>_port_t` to see which ports the service type is allowed on.
3. Add the new port: `semanage port -a -t http_port_t -p tcp 8888` (or `-m` to modify an existing binding).
4. Restart the daemon. If it still fails, `audit2allow -a -M mymod` generates a custom policy module as a last resort, or temporarily set the domain permissive with `semanage permissive -a httpd_t` while you investigate. `sealert` / `setroubleshoot` gives human-readable suggestions from the AVCs.

### L20 — Hard
**Answer:**
When a process touches a virtual address whose page isn't mapped to a physical frame (or whose mapping needs updating), the MMU raises a page fault and the kernel's fault handler runs.

- **Minor fault**: the page is already in memory (page cache, a shared lib another process already loaded, a COW page after fork, a zero page) — the kernel just updates the process's page tables to point to it. Fast, no disk I/O.
- **Major fault**: the page is not in memory and must be fetched from a backing store — disk, swap, or a memory-mapped file. The process blocks until the I/O completes. Slow.

`ps -o min_flt,maj_flt` and `vmstat` (`si/so`) expose the counts.

**Transparent Huge Pages (THP)** transparently promotes runs of 4 KiB pages to 2 MiB huge pages when possible, reducing TLB misses and page-table walks. For workloads with large, regular memory access (HPC, big in-memory computation) this can noticeably improve performance. However, THP has significant downsides: the `khugepaged` daemon and synchronous compaction/defragmentation can cause latency spikes and stalls; databases and latency-sensitive services (MongoDB, Redis, PostgreSQL, Elasticsearch, Kafka, many JVM workloads) are famously hurt by THP because a 2 MiB allocation makes copy-on-write, mlock, and fork() much more expensive, and compaction pauses show up as P99 latency. For those workloads you typically disable it, at least the `always` mode:

```
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag
```
(or `never` entirely, persisted via kernel cmdline `transparent_hugepage=never` or a tuned profile).
