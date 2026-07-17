#!/usr/bin/env bash
# Show the k3s-etcd lab VM status (and, with `ssh-config`, the per-VM SSH config).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "${HERE}/../lib.sh"

SCENARIO="$(scenario_dir k3s)"
cd "${SCENARIO}"
if [ "${1:-}" = "ssh-config" ]; then
  vagrant ssh-config
else
  vagrant status
fi
