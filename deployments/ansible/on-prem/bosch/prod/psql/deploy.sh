#!/usr/bin/env bash
# deployments/ansible/on-prem/bosch/prod/psql/deploy.sh
# Tenant-aware deploy wrapper. Path-derived context: TENANT=bosch, ENV=prod,
# SERVICE=psql. Override PROVIDER via env var (default: baremetal for prod).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../../../scripts/tenant/lib.sh"

ENV_FILE="${SCRIPT_DIR}/../../../env-vars/psql/env.bash"
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}"

tenant::init "${SCRIPT_DIR}"
tenant::run_playbook "$@"
