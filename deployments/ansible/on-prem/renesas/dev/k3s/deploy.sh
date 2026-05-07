#!/usr/bin/env bash
# deployments/ansible/on-prem/renesas/dev/k3s/deploy.sh
# Tenant-aware deploy wrapper. All logic lives in scripts/tenant/lib.sh —
# this file only declares "I am the renesas/dev/k3s leaf" by virtue of its
# path; the lib derives TENANT/ENV/SERVICE from that.
#
# Override PROVIDER via env var:
#   PROVIDER=baremetal ./deploy.sh
#   PROVIDER=proxmox   ./deploy.sh
#   PROVIDER=virtualbox ./deploy.sh    # default for dev

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../../../scripts/tenant/lib.sh"

# Optional: source per-service env overrides (kept out of git).
ENV_FILE="${SCRIPT_DIR}/../../../env-vars/k3s/env.bash"
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}"

tenant::init "${SCRIPT_DIR}"
tenant::run_playbook "$@"
