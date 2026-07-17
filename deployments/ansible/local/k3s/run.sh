#!/usr/bin/env bash
# Re-run the k3s play against an ALREADY-UP lab using the EXTERNAL qemu inventory — i.e. iterate
# on Ansible roles WITHOUT `vagrant provision` (faster; full ansible-playbook flags available).
# Regenerates ssh.config from the running VMs first, then runs against $INVENTORY.
#
# Env (from direnv .envrc / .envrc.local):
#   INVENTORY         — external inventory file (default: inventories/local/k3s/qemu/inventory.yml)
#   PLAYBOOK          — playbook              (default: k3s-etcd site.yml)
#   VAGRANT_DIR       — the running lab dir   (default: vagrant/vagrant-files/k3s)
#   ANSIBLE_VERBOSITY — v|vv|vvv              (optional)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_TOOLS_ROOT="${DEVOPS_TOOLS_ROOT:-$(cd "${HERE}/../../../.." && pwd)}"
# shellcheck source=/dev/null
source "${DEVOPS_TOOLS_ROOT}/deployments/utils/setup_env.sh"

INVENTORY="${INVENTORY:-${DEVOPS_TOOLS_ROOT}/ansible/inventories/local/k3s/qemu/inventory.yml}"
PLAYBOOK="${PLAYBOOK:-${DEVOPS_TOOLS_ROOT}/ansible/playbooks/k3s-etcd-playbooks/site.yml}"
VAGRANT_DIR="${VAGRANT_DIR:-${DEVOPS_TOOLS_ROOT}/vagrant/vagrant-files/k3s}"
INV_DIR="$(dirname "${INVENTORY}")"

[ -f "${INVENTORY}" ] || { log_error "no inventory at ${INVENTORY}"; exit 1; }
[ -f "${PLAYBOOK}" ]  || { log_error "no playbook at ${PLAYBOOK}"; exit 1; }

# Connection for the external inventory comes from ssh.config, generated from the running VMs.
if [ -x "${INV_DIR}/gen-ssh-config.sh" ]; then
  log_info "regenerating ssh.config from ${VAGRANT_DIR}"
  "${INV_DIR}/gen-ssh-config.sh" "${VAGRANT_DIR}"
fi

log_info "ansible-playbook -i ${INVENTORY} ${PLAYBOOK}"
ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" ${ANSIBLE_VERBOSITY:+"-${ANSIBLE_VERBOSITY}"}
log_success "k3s play complete"
