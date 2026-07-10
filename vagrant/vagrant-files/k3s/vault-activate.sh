#!/usr/bin/env bash
#
# vault-activate.sh — host-side Vault lifecycle orchestrator. Safe to run after EVERY
# `vagrant up`, and safe to run by hand anytime. It looks at the cluster and does the
# right thing:
#
#   • no kubeconfig / Vault not deployed  → graceful no-op (fresh destroy+up: Vault
#                                           isn't deployed until terragrunt/GitOps runs)
#   • Vault deployed, initialized=false   → operator init (rotating any STALE keystore
#                                           aside first) + unseal   ← the destroy+up case
#   • Vault deployed, initialized=true    → unseal only             ← the halt->up case
#
# WHY auto-init after a destroy is safe: a deployed Vault that reports `initialized=false`
# PROVES any vault-init.age on disk is dead — dead keys cannot belong to a Vault that says
# it was never initialized. So we can rotate the stale keystore aside and re-init without
# risking a live cluster's keys. (A live Vault these keys belonged to would report
# initialized=true and land in the unseal-only branch instead.)
#
# Usage:  ./vault-activate.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${VAULT_NAMESPACE:-vault}"
KEYFILE="${VAULT_KEYFILE:-$SCRIPT_DIR/vault-init.age}"
: "${KUBECONFIG:=$SCRIPT_DIR/kubeconfig}"
export KUBECONFIG NAMESPACE
# Propagate overrides to the sub-scripts so all three agree on namespace/keystore.
export VAULT_NAMESPACE="$NAMESPACE" VAULT_KEYFILE="$KEYFILE"

log() { printf '[vault-activate] %s\n' "$*"; }

# ── 0. Preconditions — never fail `vagrant up` over a missing tool/config ─────
command -v kubectl >/dev/null || { log "kubectl not on PATH — skipping."; exit 0; }
command -v jq      >/dev/null || { log "jq not on PATH — skipping.";      exit 0; }
if [[ ! -f "$KUBECONFIG" ]]; then
  log "no kubeconfig at $KUBECONFIG — skipping (run ./fetch-kubeconfig.sh once the cluster is up)."
  exit 0
fi

# ── 1. Is Vault even deployed here? ──────────────────────────────────────────
# Fresh destroy+up has NO Vault until the Terragrunt k3s-resources unit is applied.
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
   || ! kubectl -n "$NAMESPACE" get pod vault-0 >/dev/null 2>&1; then
  log "Vault not deployed in namespace '$NAMESPACE' yet — nothing to do."
  log "Deploy Vault (terragrunt run -- apply), then run ./vault-activate.sh (idempotent)."
  exit 0
fi

# ── 2. Wait for vault-0 to be Running (fresh boot: image pull / scheduling) ──
printf '[vault-activate] waiting for vault-0 to be Running'
for _ in $(seq 1 60); do
  phase="$(kubectl -n "$NAMESPACE" get pod vault-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$phase" == "Running" ]] && { printf ' \xE2\x9C\x93\n'; break; }
  printf '.'; sleep 3
done
echo

# ── 3. Read init state ───────────────────────────────────────────────────────
# `vault status` EXITS 2 while sealed/uninitialized but still prints valid JSON, so
# capture with `|| true` (never trip set -e) and parse separately — same pattern as
# vault-unseal.sh's seal_state().
status_json="$(kubectl -n "$NAMESPACE" exec vault-0 -- vault status -format=json 2>/dev/null || true)"
init_state="$(printf '%s' "$status_json" | jq -r '.initialized // "unknown"' 2>/dev/null || echo unknown)"

case "$init_state" in
  false)
    log "vault-0 reports initialized=false → fresh Vault (destroy+up or first bring-up)."
    if [[ -f "$KEYFILE" ]]; then
      stale="$KEYFILE.stale-$(date +%Y%m%d-%H%M%S)"
      mv "$KEYFILE" "$stale"
      log "rotated STALE keystore aside → $(basename "$stale") (old cluster's dead keys; safe to delete)."
    fi
    log "running one-time operator init..."
    "$SCRIPT_DIR/vault-init.sh"
    "$SCRIPT_DIR/vault-unseal.sh"
    log "done — fresh Vault initialized + unsealed. New keystore: $(basename "$KEYFILE")"
    ;;
  true)
    log "vault-0 reports initialized=true → unsealing existing Vault."
    if [[ ! -f "$KEYFILE" ]]; then
      log "WARNING: Vault is initialized but no keystore at $KEYFILE — cannot auto-unseal."
      log "         Restore vault-init.age from SOPS/your password manager, then re-run."
      exit 0
    fi
    "$SCRIPT_DIR/vault-unseal.sh" || log "unseal non-fatal; run ./vault-unseal.sh by hand."
    log "done."
    ;;
  *)
    log "could not read Vault init state (API not ready / pod not up yet) — skipping."
    log "Retry by hand once the pods settle: ./vault-activate.sh"
    exit 0
    ;;
esac
