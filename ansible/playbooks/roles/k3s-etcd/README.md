# roles/k3s-etcd — k3s with external etcd + HAProxy (no keepalived)

A **standalone** role tree for the k3s topology built in
`vagrant/vagrant-files/k3s/`. It is intentionally separate from the existing
`roles/k3s/` tree, which uses a **PostgreSQL datastore + HAProxy + Keepalived**.

| | `roles/k3s/` (existing) | `roles/k3s-etcd/` (this) |
|---|---|---|
| Datastore | PostgreSQL (or embedded via `--cluster-init`) | **External etcd** (dedicated box) |
| API HA | HAProxy + **Keepalived** (VRRP VIP) | **HAProxy only** (single LB, no VIP failover) |
| Servers | primary + side-server join | **co-equal peers** via the shared datastore |

## Roles

| Role | Runs on group | What it does |
|---|---|---|
| `dependencies` | `all` | packages, swap off, kernel modules, sysctl |
| `etcd` | `etcd` | single-node external etcd (binary + systemd), health-gated |
| `haproxy` | `infra` | TCP LB on `:6443` → all `server` hosts (config validated with `haproxy -c`) |
| `server` | `server` | k3s server with `--datastore-endpoint=<etcd>` (serial: 1) |
| `agent` | `agent` | k3s agent joining `https://<vip>:6443` |

## Supported OS families

`dependencies` + `haproxy` install packages by `ansible_facts['os_family']`:

| os_family | Package module | base pkgs | haproxy |
|---|---|---|---|
| `Debian` (Ubuntu/Debian) | `ansible.builtin.apt` | curl, ca-certificates | haproxy |
| `RedHat` (RHEL/Rocky/Alma) | `ansible.builtin.dnf` | curl, ca-certificates | haproxy |
| `Archlinux` | `community.general.pacman` | curl, ca-certificates | haproxy |

Everything else (etcd binary — arch-mapped for aarch64/x86_64 — k3s via
`get.k3s.io`, systemd units, sysctl, kernel modules) is OS-agnostic. **Arch note:**
the kernel must provide the `overlay` + `br_netfilter` modules (stock Arch and
Arch Linux ARM `linux-aarch64` kernels do); `community.general` must be installed
(it already ships in this repo's environment). Package names above happen to match
across all three families, so only the module/branch differs — new families are a
one-task + one-defaults-var addition per role.

## Required inventory vars

Set in the inventory's `group_vars` (see `inventories/local/k3s/qemu/group_vars/all.yml`):

- Per host: `cluster_ip` — the node's IP on the cluster LAN.
- Groups: `etcd`, `infra`, `server`, `agent` (etcd + infra may be the same host).
- `k3s_version`, `k3s_token`, `cluster_iface`, `api_port`, `load_balancer_port`, `etcd_client_port`.
- Derived (provided in the sample group_vars): `etcd_endpoint`, `load_balancer_ip`.

## Run

```bash
cd ansible
# generate SSH config for the running lab VMs first:
inventories/local/k3s/qemu/gen-ssh-config.sh
ansible-playbook -i inventories/local/k3s/qemu/inventory.yml playbooks/k3s-etcd-playbooks/site.yml
```

## Play order

`dependencies (all)` → `etcd` → `haproxy` → `server` (serial) → `agent`.

etcd must be healthy before servers install; HAProxy backends may be down until the
servers come up (agents `wait_for` the VIP). Everything is idempotent — re-runs skip
already-installed k3s/etcd.

> ⚠️ Lab posture: etcd over plain HTTP, static token, single HAProxy (SPOF). Harden
> for production: TLS + client certs on the datastore endpoint, a managed token, and
> a redundant LB (or keepalived / external LB).
