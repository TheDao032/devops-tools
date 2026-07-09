#!/usr/bin/env bash
#
# vault-init.sh — ONE-TIME initialization of the k3s-etcd lab HA-Raft Vault.
#
# Runs `vault operator init` on vault-0, then age-encrypts the unseal keys + root token
# to vault-init.age (reusing your chezmoi age key) and never writes the plaintext to disk.
# Idempotent: refuses to re-init an already-initialized Vault or overwrite an existing keystore.
#
# Usage:   ./vault-init.sh
# Then:    ./vault-unseal.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${VAULT_NAMESPACE:-vault}"
KEY_SHARES="${VAULT_KEY_SHARES:-5}"
KEY_THRESHOLD="${VAULT_KEY_THRESHOLD:-3}"
KEYFILE="${VAULT_KEYFILE:-$SCRIPT_DIR/vault-init.age}"
AGE_IDENTITY="${AGE_IDENTITY:-$HOME/.config/chezmoi/key.txt}"
: "${KUBECONFIG:=$SCRIPT_DIR/kubeconfig}"
export KUBECONFIG

for bin in kubectl age age-keygen jq; do
  command -v "$bin" >/dev/null || { echo "ERROR: '$bin' not found on PATH" >&2; exit 1; }
done
[[ -f "$AGE_IDENTITY" ]] || { echo "ERROR: age identity not found: $AGE_IDENTITY" >&2; exit 1; }

if ! kubectl -n "$NAMESPACE" get pod vault-0 >/dev/null 2>&1; then
  echo "ERROR: vault-0 not found in namespace '$NAMESPACE'." >&2
  echo "       Is Vault deployed and KUBECONFIG correct? (try ./fetch-kubeconfig.sh)" >&2
  exit 1
fi

# --- already initialized? (idempotent no-op) ---
if kubectl -n "$NAMESPACE" exec vault-0 -- vault status -format=json 2>/dev/null \
   | jq -e '.initialized == true' >/dev/null 2>&1; then
  echo "Vault is already initialized — nothing to do."
  [[ -f "$KEYFILE" ]] && echo "Keystore: $KEYFILE" || \
    echo "WARNING: no keystore at $KEYFILE — make sure you have the keys somewhere!"
  exit 0
fi

if [[ -f "$KEYFILE" ]]; then
  echo "ERROR: $KEYFILE already exists but Vault is uninitialized." >&2
  echo "       Refusing to overwrite. Remove it only if you are certain those keys are dead." >&2
  exit 1
fi

RECIPIENT="$(age-keygen -y "$AGE_IDENTITY")"
echo "Initializing Vault (key-shares=$KEY_SHARES, key-threshold=$KEY_THRESHOLD)..."

# Capture init JSON in memory only, validate, then encrypt straight to disk.
if ! init_json="$(kubectl -n "$NAMESPACE" exec vault-0 -- vault operator init \
      -key-shares="$KEY_SHARES" -key-threshold="$KEY_THRESHOLD" -format=json)"; then
  echo "ERROR: 'vault operator init' failed." >&2; exit 1
fi
printf '%s' "$init_json" | jq -e ".unseal_keys_b64 | length >= $KEY_THRESHOLD" >/dev/null \
  || { echo "ERROR: init output missing unseal keys." >&2; exit 1; }

printf '%s' "$init_json" | age -r "$RECIPIENT" -o "$KEYFILE"
unset init_json
chmod 600 "$KEYFILE"

echo "✅ Vault initialized. Keys encrypted → $KEYFILE"
echo "   Recipient: $RECIPIENT"
echo "   Inspect:   age -d -i $AGE_IDENTITY $KEYFILE | jq ."
echo "   Next:      ./vault-unseal.sh"
