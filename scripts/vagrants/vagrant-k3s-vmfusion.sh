#!/usr/bin/env bash
#
# Wrapper for the k3s + VMware Fusion scenario.
#
# Positional args (legacy, unchanged):
#   $1  vagrant action (up | halt | destroy | provision | ssh ...)
#   $2  RHEL_USERNAME  (required by the renesas tenant; pass "" otherwise)
#   $3  RHEL_PASSWORD
#   $4  vm name (optional — restrict the action to a single machine)
#   $5+ extra args forwarded to `vagrant <action>`
#
# Flags (parsed from anywhere in argv, removed before positional handling):
#   --resource-profile low|medium|high  (default: medium)
#   --tenant <name>                     (alias for TENANT env var)

set -euo pipefail

NETWORK_MODE="BRIDGE"
NETWORK_NAME="vmnet2"
PROVIDER="vmware_fusion"
VAGRANTFILE="vagrant-files/kubernetes/k3s.${PROVIDER}.Vagrantfile"
VBOX_GUEST_DISK="/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions_7.0.20.iso"

RESOURCE_PROFILE_VALUE="${RESOURCE_PROFILE:-medium}"
TENANT_VALUE="${TENANT:-}"
filtered_args=()
while (( $# > 0 )); do
  case "$1" in
    --resource-profile)
      [[ $# -lt 2 ]] && { echo "ERROR: --resource-profile requires a value (low|medium|high)" >&2; exit 2; }
      RESOURCE_PROFILE_VALUE="$2"; shift 2 ;;
    --resource-profile=*)
      RESOURCE_PROFILE_VALUE="${1#*=}"; shift ;;
    --tenant)
      [[ $# -lt 2 ]] && { echo "ERROR: --tenant requires a value" >&2; exit 2; }
      TENANT_VALUE="$2"; shift 2 ;;
    --tenant=*)
      TENANT_VALUE="${1#*=}"; shift ;;
    *)
      filtered_args+=("$1"); shift ;;
  esac
done
# macOS bash 3.2 + set -u empty-array guard.
set -- ${filtered_args[@]+"${filtered_args[@]}"}

VAGRANT_ACTION="${1:-}"
RHEL_USERNAME="${2:-}"
RHEL_PASSWORD="${3:-}"
VM_NAME="${4:-}"
if (( $# >= 4 )); then shift 4; else shift $#; fi

if [[ -z "${VAGRANT_ACTION}" ]]; then
  cat >&2 <<USAGE
usage: $0 [--resource-profile low|medium|high] [--tenant <name>] \\
          <action> <rhel_user> <rhel_pass> [vm_name] [extra args...]
USAGE
  exit 1
fi

cd vagrant
export VAGRANT_VAGRANTFILE="${VAGRANTFILE}"
export RHEL_USERNAME RHEL_PASSWORD
export PROVIDER VBOX_GUEST_DISK NETWORK_MODE
export RESOURCE_PROFILE="${RESOURCE_PROFILE_VALUE}"
[[ -n "${TENANT_VALUE}" ]] && export TENANT="${TENANT_VALUE}"

if [[ -z "${VM_NAME}" ]]; then
  exec vagrant "${VAGRANT_ACTION}" "$@"
else
  exec vagrant "${VAGRANT_ACTION}" "${VM_NAME}" "$@"
fi
