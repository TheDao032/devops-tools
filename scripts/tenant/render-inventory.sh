#!/usr/bin/env bash
# scripts/tenant/render-inventory.sh — print the effective layered inventory
# for a given tenant/env/service/provider as JSON. Useful for sanity-checking
# group_vars merging without running a playbook.
#
# Usage:
#   scripts/tenant/render-inventory.sh <tenant> <env> <service> [provider]
#
# Example:
#   scripts/tenant/render-inventory.sh renesas prod k3s baremetal

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

# Synthesize a deploy.sh-equivalent path so tenant::init derives the same context.
FAKE_DIR="${SCRIPT_DIR}/../../deployments/ansible/on-prem/${TENANT}/${ENV}/${SERVICE}"
mkdir -p "${FAKE_DIR}"   # in case the tree doesn't exist yet

PROVIDER="${PROVIDER}" tenant::init "${FAKE_DIR}"
tenant::render_inventory
