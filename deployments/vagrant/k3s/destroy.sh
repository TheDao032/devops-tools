#!/usr/bin/env bash
# Tear down the k3s-etcd lab (all 5 VMs). Runs `vagrant destroy -f --no-parallel` (sequential
# teardown, matching the --no-parallel bring-up). Extra args pass through, e.g.:
#   ./destroy.sh k3s-agent-2      # destroy a single VM
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"

SCENARIO="$(scenario_dir k3s)"
cd "${SCENARIO}"
log_warn "destroying k3s-etcd lab: vagrant destroy -f --no-parallel ${*} (${SCENARIO})"
vagrant destroy -f --no-parallel "$@"
log_success "k3s-etcd lab destroyed"
