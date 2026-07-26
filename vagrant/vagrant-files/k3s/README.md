# k3s HA lab on QEMU (vagrant-qemu)

A 5-VM k3s cluster using **external etcd** as the datastore and **HAProxy** as the
API load-balancer, driven by the `vagrant-qemu` provider. Works across a
**distro × arch matrix** — pick `distro` (ubuntu/debian/archlinux/rhel) and `arch`
(aarch64/x86_64) in `config.yaml` (or `DISTRO=` / `K3S_ARCH=` env). Apple Silicon
uses HVF, x86_64 Linux uses KVM.

Everything OS-specific is **fact-driven in Ansible** (`ansible_facts.os_family` /
`ansible_architecture`) — there are no per-distro scripts to edit. k3s/etcd/HAProxy
**and the cluster-NIC networking** are all provisioned by the **Ansible roles** in
`ansible/playbooks/roles/k3s-etcd/` (via Vagrant's `ansible` provisioner, run once
against all VMs). The `network` role renames the vmnet NIC to `k3scl0` + static IP +
`/etc/hosts`, choosing netplan (Debian) or systemd-networkd (Arch/RHEL) by fact.
Vagrant itself only boots the VMs and wires the 2nd NIC.

## Topology

| VM             | IP             | Role                                              | CPU/RAM |
|----------------|----------------|---------------------------------------------------|---------|
| `k3s-lb`       | 192.168.105.10  | external **etcd** (datastore) + **HAProxy** :6443 | 1 / 1G  |
| `k3s-server-1` | 192.168.105.11  | k3s **server** (control-plane)                    | 2 / 2G  |
| `k3s-server-2` | 192.168.105.12  | k3s **server** (control-plane)                    | 2 / 2G  |
| `k3s-agent-1`  | 192.168.105.21  | k3s **agent** (worker)                            | 2 / 2G  |
| `k3s-agent-2`  | 192.168.105.22  | k3s **agent** (worker)                            | 2 / 2G  |

```
                 agents ──┐
                          ▼
   k3s-agent-1 ┐   HAProxy :6443 (k3s-lb)  ─ roundrobin ─►  server-1 :6443
   k3s-agent-2 ┘          │                                  server-2 :6443
                          │                                      │
   both servers ──────────┴──── external etcd :2379 (k3s-lb) ◄───┘
```

Both servers use `--datastore-endpoint=http://k3s-lb:2379` (external etcd), so this is
true external-datastore HA. No keepalived — HAProxy is a single LB (fine for a lab).

## Platform add-ons (Terragrunt)

Cluster add-ons (cert-manager, External Secrets, **HashiCorp Vault** HA-Raft+TLS) are
deployed onto this lab by the Terragrunt `k3s-resources` unit in
`devops-terragrunt-environments/on-prem/fitmate/local/`. CoreDNS is left to k3s itself
(`rancher/mirrored-coredns-coredns:1.11.3`, multi-arch) — the terraform `core-dns` module
is intentionally disabled.

- **[VAULT-ACTIVATION.md](./VAULT-ACTIVATION.md)** — one-time Vault init/unseal runbook
  (Vault comes up sealed + uninitialized after `terragrunt run -- apply`).

## Prerequisites

- `qemu` + `vagrant` + the **vagrant-qemu** plugin (`vagrant plugin install vagrant-qemu`)
- **`ansible` on the host** (`brew install ansible`) — Vagrant's `ansible` provisioner
  runs the playbook from your Mac against the guests.
- A published/installed box for the `distro`+`arch` you select — see the
  `boxes[distro][arch]` matrix in `config.yaml`. Baked cells today: `archlinux/aarch64`
  (`nthedao2705/archlinux-arm64`) and `ubuntu/aarch64`. To add a cell (e.g. any distro on
  `x86_64`, or `debian`/`rhel`): bake+publish the box, drop its tag into the matrix — no
  Vagrantfile or script edits.
- **macOS only — `socket_vmnet` for inter-VM networking** (QEMU can't do multi-VM L2 on
  macOS by itself; see "How the networking works"). One-time setup:
  ```bash
  brew install socket_vmnet
  sudo brew services start socket_vmnet          # root daemon; owns the vmnet interface
  ls -l /opt/homebrew/var/run/socket_vmnet       # confirm the socket exists
  ```
  The default vmnet subnet is `192.168.105.0/24` — that's why `network.subnet` in
  `config.yaml` is `192.168.105`. On **Linux** this is not needed (socket-multicast works).

## Usage

```bash
cd vagrant-files/k3s

vagrant up                      # boots all 5 in order: lb → servers → agents
# or one at a time while iterating:
vagrant up k3s-lb
vagrant up k3s-server-1 k3s-server-2
vagrant up k3s-agent-1 k3s-agent-2

./fetch-kubeconfig.sh           # writes ./kubeconfig pointed at the HAProxy VIP
export KUBECONFIG=$PWD/kubeconfig
kubectl get nodes -o wide       # expect 2 control-plane + 2 worker = 4 nodes
```

> The LB node is **not** a Kubernetes node — it only runs etcd + HAProxy. So
> `kubectl get nodes` shows 4 nodes (2 servers + 2 agents), which is correct.

Switch architecture:

```bash
K3S_ARCH=x86_64 vagrant up      # requires box.x86_64 to be baked + installed
```

Tear down:

```bash
vagrant destroy -f
```

## Configuration

All knobs are in [`config.yaml`](./config.yaml): box names/versions, k3s + etcd
versions, the shared join token, subnet, multicast group, traefik toggle, and
per-role CPU/RAM.

## How the networking works (important)

`vagrant-qemu` has **no `private_network` support** — only user-mode SLIRP (NAT) with
SSH port-forwarding. That NAT NIC can't reach the other VMs, so each VM gets a
**second NIC** on a shared cluster LAN. The `roles/k3s-etcd/network` Ansible role
renames that NIC (found by its `cluster_mac`) to `k3scl0` and gives it a static
`192.168.105.x` address — via **netplan** (Debian) or **systemd-networkd** (Arch/RHEL),
chosen by `os_family`; k3s/flannel are pinned to `k3scl0`.

- **NIC 0** (`enp0s1`): user-mode NAT — SSH + outbound internet only.
- **NIC 1** (`k3scl0`): the cluster LAN (etcd, API, flannel VXLAN, pod traffic).

**The 2nd-NIC backend differs by host OS** (auto-selected in the Vagrantfile):

- **macOS → `socket_vmnet`.** Plain QEMU sockets (mcast *and* listen/connect) do **not**
  carry broadcast/ARP between VMs on macOS — verified: ARP stays `INCOMPLETE`, ping =
  100% loss. `tap` doesn't exist on macOS, and `vmnet-shared` needs root. So qemu is
  launched via `bin/qemu-socketvmnet.sh`, which wraps it in `socket_vmnet_client` and
  attaches the vmnet socket as `fd=3` (`-netdev socket,id=net1,fd=3`). Requires the
  `socket_vmnet` daemon (see Prerequisites).
- **Linux → socket-multicast.** `-netdev socket,id=net1,mcast=230.0.0.1:1234` forms an
  N-way L2 LAN natively — no daemon, no root.

Diagnose L2 reachability with `vagrant ssh k3s-server-1 -c "ping -c2 192.168.105.10"`.
`INCOMPLETE` ARP / 100% loss on macOS means the `socket_vmnet` daemon isn't running.

## Troubleshooting (vagrant-qemu + this arm64 box)

- **`vagrant up` hangs at "Waiting for machine to boot"** — likely the empty-NVRAM
  boot bug. If the baked box doesn't install GRUB at the UEFI fallback path
  (`/EFI/BOOT/BOOTAA64.EFI`), add a `trigger.before :up` that overwrites
  `*/edk2-arm-vars.fd` with the box's NVRAM. See the devops-architect memory note
  *"vagrant-qemu consumer-boot pitfalls — aarch64 Ubuntu"*.
- **`Permission denied (publickey)`** — the box lacks the vagrant insecure key.
  Uncomment `config.ssh.private_key_path` / `insert_key = false` in the Vagrantfile
  and point at your bake key.
- **NIC named `eth0`, DOWN** — `net_device` reverted to the mmio default. It's set to
  `virtio-net-pci` here on purpose; don't change it.
- **`vagrant ssh-config` empty during a hung boot** — read the real port from the
  QEMU process: `ps -ef | grep qemu-system | grep hostfwd`.

## Files

```
k3s/
├── Vagrantfile              # 5-node def + qemu provider + 2nd-NIC wiring + ansible provisioner
├── config.yaml             # all tunables: distro + arch selectors, boxes[distro][arch] matrix,
│                           #   versions/token/network/nodes (source of truth)
└── fetch-kubeconfig.sh     # host helper → ./kubeconfig pointed at the VIP

# In-guest setup (incl. cluster-NIC networking) lives in the Ansible roles:
#   ansible/playbooks/roles/k3s-etcd/{dependencies,network,etcd,haproxy,server,agent}/
# All OS/arch differences are handled there by facts — no per-distro scripts here.
```

k3s/etcd/HAProxy + kernel prereqs are the **Ansible roles**, not shell scripts:

```
ansible/playbooks/roles/k3s-etcd/{dependencies,etcd,haproxy,server,agent}/
ansible/playbooks/k3s-etcd-playbooks/site.yml     # the playbook Vagrant runs
ansible/inventories/local/k3s/qemu/               # standalone inventory (manual runs)
```

Vagrant passes groups + per-host `cluster_ip` + versions/token to the playbook via the
`ansible` provisioner (see the `m.vm.provision 'k3s', type: 'ansible'` block). To run the
same roles **without** Vagrant (e.g. re-provision, or on-prem hosts), use the standalone
inventory: `inventories/local/k3s/qemu/` (run `gen-ssh-config.sh` first).

> ⚠️ Lab security posture: external etcd runs over plain HTTP and the join token is
> static in `config.yaml`. Fine on an isolated lab LAN — do **not** ship this as-is.
> For real use: TLS + client certs on the datastore endpoint, a secret-managed token,
> and a second LB + keepalived (or an external LB) to remove the HAProxy SPOF.
