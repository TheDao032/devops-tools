#!/usr/bin/env bash
# Re-run ONLY the inline Ansible k3s play (limit=all) against the already-running lab,
# without recreating the VMs. Honors PLAYBOOK from the env.
#
# NOTE: `vagrant provision` has no --no-parallel flag (only --provision-with), and the k3s play
# runs on the single LAST VM anyway, so there's no parallel boot to serialize. Extra args pass
# through via "$@" if you ever need them.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"

SCENARIO="$(scenario_dir k3s)"
cd "${SCENARIO}"
log_info "re-provisioning k3s (PLAYBOOK=${PLAYBOOK:-<default>})"
vagrant provision --provision-with k3s "$@"
log_success "k3s re-provision complete"
