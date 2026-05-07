#!/usr/bin/env bash
# scripts/tenant/lib.sh — shared logic for on-prem tenant deploy scripts.
# Source this file from any deploy.sh; the deploy.sh derives TENANT/ENV/SERVICE
# from its own path so we never have to hard-code those values.
#
# Usage from a deploy.sh:
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../../../../../scripts/tenant/lib.sh"
#   tenant::init "${SCRIPT_DIR}"        # sets TENANT, ENV, SERVICE, REPO_ROOT, ...
#   tenant::run_playbook                  # builds inventory chain, runs ansible-playbook

set -euo pipefail

# --- logging helpers ---------------------------------------------------------
log_info()  { printf "[INFO]  %s %s\n"  "$(date -u +%FT%TZ)" "$*" >&2; }
log_warn()  { printf "[WARN]  %s %s\n"  "$(date -u +%FT%TZ)" "$*" >&2; }
log_error() { printf "[ERROR] %s %s\n"  "$(date -u +%FT%TZ)" "$*" >&2; }
log_fatal() { log_error "$@"; exit 1; }

# --- tenant::init: derive context from caller's path -------------------------
# Expects deploy.sh to live at:
#   deployments/ansible/on-prem/<tenant>/<env>/<service>/deploy.sh
tenant::init() {
  local script_dir="${1:-}"
  [[ -z "${script_dir}" ]] && log_fatal "tenant::init: SCRIPT_DIR required"

  # Walk up to repo root (looks for ansible/ alongside scripts/)
  local cur="${script_dir}"
  while [[ "${cur}" != "/" && ! -d "${cur}/ansible" ]]; do
    cur="$(dirname "${cur}")"
  done
  [[ "${cur}" == "/" ]] && log_fatal "tenant::init: cannot locate repo root from ${script_dir}"

  REPO_ROOT="${cur}"
  ANSIBLE_DIR="${REPO_ROOT}/ansible"
  INVENTORIES_DIR="${ANSIBLE_DIR}/inventories"

  # Parse the script path: .../deployments/ansible/on-prem/<tenant>/<env>/<service>/deploy.sh
  local rel="${script_dir#${REPO_ROOT}/}"
  IFS='/' read -ra parts <<<"${rel}"
  # Expected layout: deployments / ansible / on-prem / <tenant> / <env> / <service>
  if [[ "${parts[0]}" != "deployments" || "${parts[2]}" != "on-prem" ]]; then
    log_fatal "tenant::init: deploy.sh must live under deployments/ansible/on-prem/<tenant>/<env>/<service>/, got ${rel}"
  fi
  TENANT="${parts[3]}"
  ENV="${parts[4]}"
  SERVICE="${parts[5]}"

  # PROVIDER is supplied by env or defaults to baremetal for prod, virtualbox for dev.
  if [[ -z "${PROVIDER:-}" ]]; then
    if [[ "${ENV}" == "prod" ]]; then PROVIDER="baremetal"; else PROVIDER="virtualbox"; fi
  fi

  export TENANT ENV SERVICE PROVIDER REPO_ROOT ANSIBLE_DIR INVENTORIES_DIR
  export ANSIBLE_TENANT="${TENANT}"   # used by ansible.cfg.on-prem for fact cache + control_path
  export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg.on-prem"

  log_info "tenant=${TENANT} env=${ENV} service=${SERVICE} provider=${PROVIDER}"
}

# --- tenant::vault_password_file ---------------------------------------------
# Returns the path to the tenant's ansible-vault password file. Convention:
#   ~/.config/ansible-vault/<tenant>
# This indirection means we never embed the password in the repo, and
# different tenants have different password files (compliance: blast-radius
# isolation between Renesas and Bosch).
tenant::vault_password_file() {
  local f="${HOME}/.config/ansible-vault/${TENANT}"
  if [[ ! -r "${f}" ]]; then
    log_warn "vault password file ${f} not present — encrypted inventories will fail to decrypt"
  fi
  printf "%s" "${f}"
}

# --- tenant::inventory_chain --------------------------------------------------
# Builds the layered inventory: -i path1 -i path2 -i ...
# Order matters: shared -> company -> leaf (most specific wins).
tenant::inventory_chain() {
  local shared="${INVENTORIES_DIR}/on-prem/_shared"
  local company="${INVENTORIES_DIR}/on-prem/${TENANT}/_company"
  local leaf="${INVENTORIES_DIR}/on-prem/${TENANT}/${ENV}/${SERVICE}/${PROVIDER}"

  [[ -d "${shared}"  ]] || log_fatal "missing shared layer: ${shared}"
  [[ -d "${company}" ]] || log_fatal "missing company layer: ${company}"
  [[ -d "${leaf}"    ]] || log_fatal "missing leaf inventory: ${leaf}"
  [[ -f "${leaf}/inventory.yml" ]] || log_fatal "leaf has no inventory.yml: ${leaf}"

  printf -- "-i %s -i %s -i %s/inventory.yml" "${shared}" "${company}" "${leaf}"
}

# --- tenant::run_playbook -----------------------------------------------------
# Resolves the playbook for SERVICE and runs it against the inventory chain.
tenant::run_playbook() {
  local playbook="${ANSIBLE_DIR}/playbooks/${SERVICE}-playbooks/site.yml"
  [[ -f "${playbook}" ]] || log_fatal "playbook not found: ${playbook}"

  local vault_file
  vault_file="$(tenant::vault_password_file)"

  # shellcheck disable=SC2046
  ANSIBLE_VAULT_PASSWORD_FILE="${vault_file}" \
    ansible-playbook \
      $(tenant::inventory_chain) \
      "${playbook}" \
      "$@"
}

# --- tenant::render_inventory -------------------------------------------------
# Useful for debugging: prints the effective inventory as JSON.
tenant::render_inventory() {
  local vault_file
  vault_file="$(tenant::vault_password_file)"
  # shellcheck disable=SC2046
  ANSIBLE_VAULT_PASSWORD_FILE="${vault_file}" \
    ansible-inventory $(tenant::inventory_chain) --list
}
