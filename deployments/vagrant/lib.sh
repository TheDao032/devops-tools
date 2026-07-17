#!/usr/bin/env bash
# Shared helpers for the deployments/vagrant/<scenario> wrappers.
# Sourced (not executed) by up.sh / provision.sh / destroy.sh / status.sh.

# Repo root: two levels up from deployments/vagrant/ (unless direnv already exported it).
DEVOPS_TOOLS_ROOT="${DEVOPS_TOOLS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Logging helpers (log_info / log_warn / log_error / log_success / log_debug).
# shellcheck source=/dev/null
source "${DEVOPS_TOOLS_ROOT}/deployments/utils/setup_env.sh"

# ensure_plugins <plugin>...  — install any vagrant plugins that aren't present.
ensure_plugins() {
  local plugin
  for plugin in "$@"; do
    if vagrant plugin list 2>/dev/null | grep -q "^${plugin} "; then
      log_info "vagrant plugin '${plugin}' already installed"
    else
      log_info "installing vagrant plugin '${plugin}'..."
      vagrant plugin install "${plugin}" || { log_error "failed to install '${plugin}'"; exit 1; }
    fi
  done
}

# scenario_dir <name>  — echo vagrant/vagrant-files/<name>, or fail if it has no Vagrantfile.
scenario_dir() {
  local name="$1"
  local dir="${DEVOPS_TOOLS_ROOT}/vagrant/vagrant-files/${name}"
  [ -f "${dir}/Vagrantfile" ] || { log_error "no Vagrantfile at ${dir}"; exit 1; }
  printf '%s' "${dir}"
}
