#!/usr/bin/env bash
# scripts/tenant/load-secrets.sh — decrypt and source a tenant's secrets.vault.yml
# into the calling shell as exported variables. Intended for ad-hoc debugging,
# NOT for production deploys (deploy.sh uses ansible-vault directly).
#
# Usage:
#   eval "$(scripts/tenant/load-secrets.sh renesas)"
#
# This requires:
#   - ~/.config/ansible-vault/<tenant> exists and contains the vault password
#   - ansible/inventories/on-prem/<tenant>/_company/secrets.vault.yml exists
#     and is ansible-vault-encrypted

set -euo pipefail

TENANT="${1:-}"
[[ -z "${TENANT}" ]] && { echo "usage: $(basename "$0") <tenant>" >&2; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VAULT_FILE="${REPO_ROOT}/ansible/inventories/on-prem/${TENANT}/_company/secrets.vault.yml"
PASS_FILE="${HOME}/.config/ansible-vault/${TENANT}"

[[ -r "${PASS_FILE}"  ]] || { echo "missing password file: ${PASS_FILE}" >&2; exit 1; }
[[ -r "${VAULT_FILE}" ]] || { echo "missing vault file: ${VAULT_FILE}" >&2; exit 1; }

# Decrypt to stdout, parse YAML keys, emit `export KEY="VAL"` lines.
# We use python3 instead of yq to avoid an extra dependency. Multiline values
# (private keys) survive because we use json.dumps for shell-safe quoting.
ansible-vault view --vault-password-file "${PASS_FILE}" "${VAULT_FILE}" | \
python3 -c '
import sys, yaml, json
data = yaml.safe_load(sys.stdin) or {}
for k, v in data.items():
    if not isinstance(v, str):
        v = json.dumps(v)
    # JSON-encode strings to handle newlines, quotes, etc.
    print(f"export {k}={json.dumps(v)}")
'
