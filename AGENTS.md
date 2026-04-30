# Repository Guidelines

## Project Structure & Module Organization
`ansible/` holds inventories, playbooks, and reusable roles for `k3s`, `vault`, `postgresql`, `openldap`, and browser setup. `deployments/ansible/<env>/<service>/deploy.sh` contains the main entrypoints for local and dev environments. `vagrant/` stores provider-specific Vagrantfiles and Ruby helpers. `docker-composes/`, `dockerfiles/`, `kubernetes-templates/`, `config/`, and `data/` contain local infrastructure assets. The main Python service lives in `services/metric-collector/` with app code, Alembic migrations, and tests under `tests/integration/`.

## Build, Test, and Development Commands
Run commands from the repository root unless noted.

- `pip install -r requirements.txt` installs top-level Python dependencies generated from `pyproject.toml`.
- `pip install -r services/metric-collector/requirements.txt` installs the service runtime dependencies.
- `docker compose -f docker-composes/docker-compose.psql.yml up -d` starts a local PostgreSQL stack; swap in `openldap` or `vault` as needed.
- `python -m pytest services/metric-collector/tests/integration` runs the checked-in integration tests.
- `flake8 services/metric-collector` runs the Python linter used in CI.
- `ENVIRONMENT=local PROVIDER=virtualbox ./deployments/ansible/local/k3s/deploy.sh` is the pattern for provisioning stacks; equivalent scripts exist for `psql` and `vault`.

## Coding Style & Naming Conventions
Use 4-space indentation in Python and keep lines within the Flake8 limit of 120 characters. Prefer `snake_case` for Python modules, functions, and variables; keep shell files as lowercase `deploy.sh` or `env.bash`; keep Ansible inventory and playbook files descriptive, such as `master-site.yml` or `dynamic_inventory.py`. Reuse existing directory naming based on environment and service, for example `deployments/ansible/local/vault/`.

## Testing Guidelines
Add Python tests beside the service in `services/metric-collector/tests/`. Follow the existing `test_*.py` naming pattern and keep fixtures local unless reused broadly. For infrastructure changes, validate the target inventory first with `uv run ansible/inventories/<env>/<service>/<provider>/dynamic_inventory.py --list`, then run the relevant playbook or deploy script.

## Commit & Pull Request Guidelines
Recent history uses short, imperative prefixes such as `build:` and `feature:`. Keep commit subjects concise and scoped, for example `build: update vault playbooks`. PRs should describe the target environment, affected services, changed paths, manual verification steps, and any required env vars or credentials. Include screenshots only when UI-facing tooling changes.

## Security & Configuration Tips
Treat `.env`, `env.bash`, certificate material, and Vault/OpenLDAP config as sensitive. Use the `.example` files in `deployments/ansible/*/env-vars/` as templates, and avoid committing new secrets, private keys, or host-specific values.
