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

# Ansible deployment pattern
ENVIRONMENT=local PROVIDER=virtualbox ./deployments/ansible/local/k3s/deploy.sh
# Swap k3s for psql or vault; swap local for dev

# Validate Ansible dynamic inventory
uv run ansible/inventories/<env>/<service>/<provider>/dynamic_inventory.py --list

# Vagrant syntax check before running
ruby -c vagrant/utils/env.rb
ruby -c vagrant/vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile

# Vagrant scenario execution (from vagrant/ directory)
cd vagrant
VAGRANT_VAGRANTFILE=vagrant-files/kubernetes/k3s.virtualbox.Vagrantfile \
  PROVIDER=virtualbox NETWORK_MODE=NAT NUM_SERVERS=2 NUM_AGENTS=1 \
  vagrant up --provider virtualbox --provision
```

## Architecture

### Ansible (`ansible/`)

- **Inventories** at `ansible/inventories/<env>/<service>/<provider>/` — two environments: `local` and `dev`. Services: `k3s`, `psql`, `vault`, `browser`. Providers: `virtualbox`, `vmware_fusion`, `docker`.
- **Dynamic inventories** are Python scripts (`dynamic_inventory.py`) that generate host lists from Vagrant or provider state.
- **Playbooks** at `ansible/playbooks/<service>-playbooks/` — organized by service with reusable roles under `ansible/playbooks/roles/`.
- **Roles** cover: k3s (server/agent/load-balancer with HAProxy+Keepalived), PostgreSQL (Citus coordinator/worker, repmgr replication, pgbouncer), Vault, OpenLDAP, nginx, browser automation, and base dependencies.

### Deployments (`deployments/`)

Entry-point `deploy.sh` scripts at `deployments/ansible/<env>/<service>/deploy.sh`. Each environment has `env-vars/` with `.bash.example` templates — copy to `.bash` and fill in values before running. The `deployments/utils/setup_env.sh` helper loads env vars.

### Vagrant (`vagrant/`)

Uses a clean-architecture layered design:
- **Domain** (`vagrant/domain/plan.rb`): machine, network, and cluster plan objects.
- **Application** (`vagrant/application/`): `resource_allocator.rb` for sizing, `cluster_plan_builder.rb` for plan construction.
- **Infrastructure** (`vagrant/infrastructure/vagrant_plan_applier.rb`): renders plans into provider-specific Vagrant DSL.
- **Scenario files** (`vagrant/vagrant-files/`): thin entrypoints declaring what to build (k3s, psql, foreman, grafana-alloy, sentinel-one). Edit scenario intent here, not provider logic.
- **Providers** (`vagrant/providers/`): Ruby helpers per provider (virtualbox, vmware_fusion, docker) with OS-specific box configs.

Key env vars: `PROVIDER`, `NETWORK_MODE`, `NUM_SERVERS`, `NUM_AGENTS`, `ARCH`, `IP_NW`, `VBOX_GUEST_DISK`, `RHEL_USERNAME`/`RHEL_PASSWORD`.

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

Never commit `.env`, `env.bash`, certificates, or Vault/OpenLDAP credentials. Use the `.example` templates in `deployments/ansible/*/env-vars/`.
