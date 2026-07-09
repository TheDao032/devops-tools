#!/usr/bin/env bash
#
# vault-unseal.sh — unseal the k3s-etcd lab HA-Raft Vault pods after a restart.
#
# Decrypts the unseal keys from vault-init.age (via your chezmoi age key) and feeds the
# threshold to each vault pod. Idempotent: skips pods that are already unsealed. Run this
# after every `vagrant up` (or wire it into the Vagrant provisioner).
#
# Usage:   ./vault-unseal.sh                # unseal vault-0 vault-1 vault-2
#          ./vault-unseal.sh vault-1        # just one pod
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${VAULT_NAMESPACE:-vault}"
KEYFILE="${VAULT_KEYFILE:-$SCRIPT_DIR/vault-init.age}"
AGE_IDENTITY="${AGE_IDENTITY:-$HOME/.config/chezmoi/key.txt}"
: "${KUBECONFIG:=$SCRIPT_DIR/kubeconfig}"
export KUBECONFIG

for bin in kubectl age jq; do
  command -v "$bin" >/dev/null || { echo "ERROR: '$bin' not found on PATH" >&2; exit 1; }
done
[[ -f "$KEYFILE" ]]      || { echo "ERROR: keystore $KEYFILE not found — run ./vault-init.sh first" >&2; exit 1; }
[[ -f "$AGE_IDENTITY" ]] || { echo "ERROR: age identity not found: $AGE_IDENTITY" >&2; exit 1; }

if [[ $# -gt 0 ]]; then PODS=("$@"); else PODS=(vault-0 vault-1 vault-2); fi

# Graceful no-op if Vault isn't deployed here (fresh cluster before `terragrunt apply`).
# This lets the script be wired into `vagrant up` without failing an un-Vaulted cluster.
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "namespace '$NAMESPACE' not found — Vault not deployed here. Nothing to unseal."
  exit 0
fi

# After a reboot the pods may still be starting — wait for vault-0 to be Running (<=3 min).
printf 'waiting for vault-0 to be Running'
for _ in $(seq 1 60); do
  phase="$(kubectl -n "$NAMESPACE" get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Running" ]] && { printf ' \xE2\x9C\x93\n'; break; }
  printf '.'; sleep 3
done
echo

# Decrypt the first `threshold` unseal keys into an array (bash 3.2-compatible — no mapfile).
KEYS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && KEYS+=("$line")
done < <(age -d -i "$AGE_IDENTITY" "$KEYFILE" | jq -r '.unseal_keys_b64[]')
[[ "${#KEYS[@]}" -ge 3 ]] || { echo "ERROR: decrypted ${#KEYS[@]} keys, expected >= 3" >&2; exit 1; }

# Returns "true"/"false"; never trips set -e (vault status exits 2 while sealed).
seal_state() {
  local pod="$1" js
  js="$(kubectl -n "$NAMESPACE" exec "$pod" -- vault status -format=json 2>/dev/null || true)"
  printf '%s' "$js" | jq -r '.sealed // true' 2>/dev/null || echo true
}

rc=0
for pod in "${PODS[@]}"; do
  if ! kubectl -n "$NAMESPACE" get pod "$pod" >/dev/null 2>&1; then
    echo "• $pod: not found — skipping"; continue
  fi
  if [[ "$(seal_state "$pod")" == "false" ]]; then
    echo "• $pod: already unsealed ✓"; continue
  fi
  echo "• $pod: unsealing..."
  i=0
  for k in "${KEYS[@]}"; do
    kubectl -n "$NAMESPACE" exec "$pod" -- vault operator unseal "$k" >/dev/null 2>&1 || true
    i=$((i + 1))
    [[ "$(seal_state "$pod")" == "false" ]] && break   # stop once threshold reached
  done
  # The API blips for ~1-2s during the seal→unseal transition (status calls fail and
  # fall through to the `// true` default), so poll a few times before declaring failure.
  unsealed=false
  for _ in 1 2 3 4 5 6; do
    [[ "$(seal_state "$pod")" == "false" ]] && { unsealed=true; break; }
    sleep 2
  done
  if $unsealed; then
    echo "  → unsealed ✓"
  else
    echo "  → STILL SEALED ✗ — check: kubectl -n $NAMESPACE logs $pod"; rc=1
  fi
done

unset KEYS
echo "Done."
exit "$rc"
