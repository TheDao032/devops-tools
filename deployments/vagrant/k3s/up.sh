#!/usr/bin/env bash
# Bring up the k3s-etcd HA lab (5 QEMU VMs) and provision k3s INLINE via Ansible.
# The Vagrantfile's ansible provisioner runs once, limit=all, on the last VM — so a single
# `vagrant up` boots every node AND runs the whole k3s play against all of them.
#
# Env (from direnv .envrc / .envrc.local):
#   PLAYBOOK          — playbook the Vagrantfile runs   (default: k3s-etcd site.yml)
#   K3S_ARCH          — guest arch (aarch64|x86_64)      (default: host arch)
#   ANSIBLE_VERBOSITY — v|vv|vvv                          (optional)
#
# Args passed to this script are forwarded VERBATIM to `vagrant up`, e.g.:
#   ./up.sh                        # default (parallel — vagrant's normal behavior)
#   ./up.sh --no-parallel          # sequential bring-up (recommended for vagrant-qemu:
#                                  #   it can race/fail its SSH-port auto-correct in parallel)
#   ./up.sh --provision            # force re-provision an existing lab
#   ./up.sh k3s-agent-2            # bring up / retry a single VM (e.g. one that timed out)
#   ./up.sh k3s-lb k3s-server-1    # subset (NB: the ansible play only fires on the LAST VM)
#
# NOTE: --no-parallel is NO LONGER forced — pass it yourself when you want it. If a
# parallel `up` flakes on SSH-port auto-correct, re-run with --no-parallel.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"

SCENARIO="$(scenario_dir k3s)"

ensure_plugins vagrant-qemu

log_info "scenario   = ${SCENARIO}"
log_info "PLAYBOOK   = ${PLAYBOOK:-<Vagrantfile default>}"
log_info "K3S_ARCH   = ${K3S_ARCH:-<host arch>}"
log_info "command    = vagrant up ${*:-<no extra args>}"

# Stay in the scenario dir so the Vagrantfile's relative provision/ paths + .vagrant/ state resolve.
cd "${SCENARIO}"
vagrant up "$@"

log_success "k3s-etcd lab up. Fetch kubeconfig with: ${SCENARIO}/fetch-kubeconfig.sh"
