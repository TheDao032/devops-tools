#!/usr/bin/env bash
# scripts/tenant/compliance-check.sh — dry-run the compliance role against a
# tenant/env/service inventory and report what WOULD change. No mutations.
#
# Usage:
#   scripts/tenant/compliance-check.sh <tenant> <env> <service> [provider]

set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $(basename "$0") <tenant> <env> <service> [provider]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib.sh"

TENANT="$1"
ENV="$2"
SERVICE="$3"
PROVIDER="${4:-}"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FAKE_DIR="${REPO_ROOT}/deployments/ansible/on-prem/${TENANT}/${ENV}/${SERVICE}"
mkdir -p "${FAKE_DIR}"

PROVIDER="${PROVIDER}" tenant::init "${FAKE_DIR}"

VAULT_FILE="$(tenant::vault_password_file)"

# An ad-hoc playbook that only invokes the compliance role.
TMP_PLAY="$(mktemp -t compliance-check.XXXXXX.yml)"
trap 'rm -f "${TMP_PLAY}"' EXIT
cat >"${TMP_PLAY}" <<'YAML'
- hosts: all
  gather_facts: true
  roles:
    - role: compliance
      tags: [compliance]
YAML

# shellcheck disable=SC2046
ANSIBLE_VAULT_PASSWORD_FILE="${VAULT_FILE}" \
  ansible-playbook \
    $(tenant::inventory_chain) \
    "${TMP_PLAY}" \
    --check --diff \
    --tags compliance \
    "$@"
