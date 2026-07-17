# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a DevOps infrastructure toolkit for provisioning and managing local/dev environments. It orchestrates k3s clusters, PostgreSQL (with Citus and repmgr), HashiCorp Vault, OpenLDAP, and browser automation setups using Ansible, Vagrant, and Docker Compose.

## Build & Development Commands

All commands run from the repository root.

```bash
# Python dependencies (Python 3.11, managed via uv)
pip install -r requirements.txt                              # top-level deps
pip install -r services/metric-collector/requirements.txt    # service deps

# Local infrastructure stacks via Docker Compose
docker compose -f docker-composes/docker-compose.psql.yml up -d
docker compose -f docker-composes/docker-compose.openldap.yml up -d
docker compose -f docker-composes/docker-compose.vault.yml up -d

# Linting
flake8 services/metric-collector    # 120-char line limit

# Tests (integration only)
python -m pytest services/metric-collector/tests/integration

# k3s lab (k3s-etcd HA, 5 QEMU VMs) — env comes from direnv (.envrc / .envrc.local)
direnv allow                              # once; sets PLAYBOOK / INVENTORY / RESOURCE_PROFILE
./deployments/vagrant/k3s/up.sh           # boot VMs + provision k3s INLINE (ansible limit=all)
./deployments/vagrant/k3s/provision.sh    # re-run the k3s play (via vagrant provision)
./deployments/vagrant/k3s/destroy.sh
./deployments/ansible/local/k3s/run.sh    # re-run the play WITHOUT vagrant (external qemu inventory)

# On-prem tenant deploys (ansible only, real hosts)
./deployments/ansible/on-prem/<tenant>/<env>/<service>/deploy.sh

# Validate Ansible dynamic inventory
uv run ansible/inventories/<env>/<service>/<provider>/dynamic_inventory.py --list

# Vagrant syntax check before running
ruby -c vagrant/vagrant-files/k3s/Vagrantfile

# Raw vagrant (the wrappers just cd here + run this; PLAYBOOK/K3S_ARCH honored from the env)
cd vagrant/vagrant-files/k3s && vagrant up
```

## Architecture

### Ansible (`ansible/`)

- **Inventories** at `ansible/inventories/<env>/<service>/<provider>/` — two environments: `local` and `dev`. Services: `k3s`, `psql`, `vault`, `browser`. Providers: `virtualbox`, `vmware_fusion`, `docker`.
- **Dynamic inventories** are Python scripts (`dynamic_inventory.py`) that generate host lists from Vagrant or provider state.
- **Playbooks** at `ansible/playbooks/<service>-playbooks/` — organized by service with reusable roles under `ansible/playbooks/roles/`.
- **Roles** cover: k3s (server/agent/load-balancer with HAProxy+Keepalived), PostgreSQL (Citus coordinator/worker, repmgr replication, pgbouncer), Vault, OpenLDAP, nginx, browser automation, and base dependencies.

### Deployments (`deployments/`)

- **`deployments/vagrant/<scenario>/`** — thin wrappers around the `vagrant/vagrant-files/<scenario>/` labs (currently `k3s`). Each has `up.sh` / `provision.sh` / `destroy.sh` / `status.sh`; they `cd` into the scenario dir and run vagrant, adding plugin-ensure + logging. `up.sh` provisions **inline** — `vagrant up` triggers the Vagrantfile's ansible provisioner (`limit: all`, on the last VM), so one command boots all nodes AND runs the whole play. Shared helpers in `deployments/vagrant/lib.sh`.
- **`deployments/ansible/local/k3s/run.sh`** — re-run the k3s play against an already-up lab via the **external** `inventories/local/k3s/qemu` inventory (regenerates `ssh.config` from the running VMs first) — faster iteration than `vagrant provision`.
- **`deployments/ansible/on-prem/<tenant>/<env>/<service>/deploy.sh`** — ansible-only deploys against real on-prem hosts (no vagrant); each tenant has its own `env-vars/`.
- **Env comes from direnv** — `.envrc` (scenario defaults) + `.envrc.local` (per-machine/secret overrides); both gitignored, `.envrc.local.example` is the tracked template. Sets `PLAYBOOK`, `INVENTORY`, `RESOURCE_PROFILE`, etc.
- `deployments/utils/setup_env.sh` provides the logging helpers the wrappers source.

> Retired: the old two-phase `deployments/ansible/{local,dev}/<service>/deploy.sh` (separate `vagrant up` + `ansible-playbook`, pointing at the removed `vagrant-files/kubernetes/` scenario).

### Vagrant (`vagrant/`)

Uses a clean-architecture layered design:
- **Domain** (`vagrant/domain/plan.rb`): machine, network, and cluster plan objects.
- **Application** (`vagrant/application/`): `resource_allocator.rb` for sizing, `cluster_plan_builder.rb` for plan construction.
- **Infrastructure** (`vagrant/infrastructure/vagrant_plan_applier.rb`): renders plans into provider-specific Vagrant DSL.
- **Scenario files** (`vagrant/vagrant-files/`): thin entrypoints declaring what to build (k3s, psql, foreman, grafana-alloy, sentinel-one). Edit scenario intent here, not provider logic.
- **Providers** (`vagrant/providers/`): Ruby helpers per provider (virtualbox, vmware_fusion, docker) with OS-specific box configs.

Key env vars (legacy virtualbox scenarios): `PROVIDER`, `NETWORK_MODE`, `NUM_SERVERS`, `NUM_AGENTS`, `ARCH`, `IP_NW`, `VBOX_GUEST_DISK`, `RHEL_USERNAME`/`RHEL_PASSWORD`.

The **k3s-etcd QEMU scenario** (`vagrant-files/k3s/`) is **self-contained** (not the layered design above): nodes/versions/subnet come from its own `config.yaml`, and it provisions k3s inline via Ansible during `vagrant up`. Overridable via direnv: `K3S_ARCH`, `PLAYBOOK` (the inline play), `RESOURCE_PROFILE`, plus `BOX_*` (see `.envrc.local.example`). Driven by `deployments/vagrant/k3s/*.sh`.

### Metric Collector Service (`services/metric-collector/`)

Python service with Alembic migrations, PostgreSQL database layer, Prometheus integration, and Docker Compose for local dev. Has its own `pyproject.toml`, `Dockerfile`, and `requirements.txt`.

### Docker & Kubernetes

- `dockerfiles/`: base images (common, kubespray, vagrant).
- `docker-composes/`: local stacks for psql, openldap, vault with supporting config/data.
- `kubernetes-templates/`: K8s manifests (e.g., node-local-dns).

## Coding Conventions

- Python: 4-space indent, 120-char line limit (flake8), `snake_case` for modules/functions/variables.
- Shell: lowercase filenames (`deploy.sh`, `env.bash`).
- Ansible: descriptive filenames (`master-site.yml`, `dynamic_inventory.py`).
- Commits: short imperative prefix (`build:`, `feature:`, `fix:`).

## Sensitive Files

Never commit `.env`, `.envrc`, `.envrc.local`, `env.bash`, certificates, or Vault/OpenLDAP credentials. `.envrc`/`.envrc.local` are gitignored (only `.envrc.local.example` is tracked); on-prem tenant secrets use the `.example` templates in `deployments/ansible/on-prem/*/env-vars/`.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
