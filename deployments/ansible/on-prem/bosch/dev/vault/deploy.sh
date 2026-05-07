#!/usr/bin/env bash
# deployments/ansible/on-prem/bosch/dev/vault/deploy.sh
# Tenant-aware deploy wrapper. Path-derived context: TENANT=bosch, ENV=dev,
# SERVICE=vault. Override PROVIDER via env var (default: virtualbox for dev).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../../../scripts/tenant/lib.sh"

ENV_FILE="${SCRIPT_DIR}/../../../env-vars/vault/env.bash"
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}"

tenant::init "${SCRIPT_DIR}"
tenant::run_playbook "$@"
