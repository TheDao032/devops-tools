#!/usr/bin/env bash
# Gracefully power off the k3s-etcd lab VMs (all 5) WITHOUT deleting them — the
# disk state is preserved, so `./up.sh` brings them back where they left off (no
# re-provision needed). Use `./destroy.sh` to delete the VMs entirely instead.
#
# Runs `vagrant halt` (ACPI graceful shutdown). NB: unlike up/destroy, `vagrant
# halt` does NOT accept --no-parallel. Extra args pass through, e.g.:
#   ./halt.sh k3s-agent-2      # halt a single VM
#   ./halt.sh -f               # force (pull power) if a guest won't shut down cleanly
#
# KNOWN QUIRK: the vagrant-qemu plugin sometimes leaves an orphaned
# qemu-system-aarch64 process after halt that squats on the VM's forwarded SSH
# port, which then breaks the next `up`. If `./up.sh` later complains about a
# port already in use, check `pgrep -fl qemu-system-aarch64` and kill the
# stragglers (safe on this Mac — colima runs the vz driver, not qemu).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"

SCENARIO="$(scenario_dir k3s)"
cd "${SCENARIO}"
log_info "halting k3s-etcd lab: vagrant halt ${*} (${SCENARIO})"
vagrant halt "$@"
log_success "k3s-etcd lab halted (disk preserved; run ./up.sh to resume)"
