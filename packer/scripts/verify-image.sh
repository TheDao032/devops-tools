#!/usr/bin/env bash
# Post-bake sanity check.
#
# Mounts (or briefly boots) a baked artifact and asserts the compliance flags
# we care about. Intended to run in CI after a successful packer build.
#
# Usage:
#   ./scripts/verify-image.sh <tenant> <path-to-artifact>
#
# Caveat: this is a stub framework. The actual mount logic depends on the
# artifact format (.box / .qcow2 / .ova). Fill in per-format checks as you
# adopt them. Returns non-zero on any failed assertion so CI fails the build.

set -euo pipefail

TENANT="${1:-}"
ARTIFACT="${2:-}"

if [[ -z "${TENANT}" || -z "${ARTIFACT}" ]]; then
  echo "Usage: $0 <tenant> <artifact-path>"
  exit 2
fi

if [[ ! -e "${ARTIFACT}" ]]; then
  echo "ERROR: artifact not found: ${ARTIFACT}"
  exit 3
fi

# Expectations per tenant (kept here so verify and bake share one source).
case "${TENANT}" in
  renesas)
    EXPECTED_PROFILE="cis-l2"
    EXPECTED_FIPS="true"
    ;;
  bosch)
    EXPECTED_PROFILE="cis-l1"
    EXPECTED_FIPS="false"
    ;;
  *)
    echo "ERROR: unknown tenant '${TENANT}'"
    exit 4
    ;;
esac

# TODO: Wire actual mount/boot logic per artifact type.
#
# Recommended approach — boot the artifact briefly with libvirt or VBoxManage
# in headless mode, ssh as the bootstrap user, cat /etc/image-metadata, then
# halt. Pseudocode:
#
#   start_vm "${ARTIFACT}"
#   wait_for_ssh
#   META="$(ssh ${VM} cat /etc/image-metadata)"
#   stop_vm
#   echo "${META}" | grep -q "compliance_profile=${EXPECTED_PROFILE}"
#   echo "${META}" | grep -q "fips_mode=${EXPECTED_FIPS}"
#   ssh ${VM} fips-mode-setup --check  # for renesas
#   ssh ${VM} findmnt /tmp | grep -E "nosuid|nodev|noexec"  # for cis-l2
#
# Until that's implemented, this script just announces what it WOULD check.

cat <<EOF
[verify-image] tenant=${TENANT}
[verify-image] artifact=${ARTIFACT}
[verify-image] expected: profile=${EXPECTED_PROFILE} fips_mode=${EXPECTED_FIPS}
[verify-image] (TODO: implement mount/boot + assertion logic)
EOF

exit 0
