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
