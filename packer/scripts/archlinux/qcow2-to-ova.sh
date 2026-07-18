#!/usr/bin/env bash
# qcow2-to-ova.sh — wrap the ALARM aarch64 base qcow2 into a VirtualBox .ova base.
#
# ⚠️  EXPERIMENTAL — needs first-bake validation on your host.
#     VirtualBox's aarch64 support (7.1+) and its CLI surface for ARM VMs
#     (--platform-architecture arm, armv8virtual chipset) are newer and vary by
#     point release. The qemu/libvirt path is the primary, reliable one; this
#     exists so the `virtualbox` provider has a base to feed stage 2's
#     `virtualbox-ovf` source. If VBoxManage rejects a flag, check `VBoxManage
#     --version` and the runbook's VirtualBox notes.
#
# WHY A CONVERTER (not a Packer virtualbox-iso base like Ubuntu):
#   Ubuntu's VBox base is installed from an ISO by `virtualbox-iso`. ALARM has no
#   ISO, so there is nothing for `virtualbox-iso` to boot. Instead we take the
#   qcow2 that STAGE 1 already produced, convert it to VMDK, wrap it in a throwaway
#   VBox VM configured for arm64, and export an .ova. Stage 2's `virtualbox-ovf`
#   source then imports that .ova, provisions it, and re-exports the final box.
#
# INPUT (env):  BASE_QCOW2=<path to the stage-1 qcow2>   BASE_VERSION=<version>
# OUTPUT:       output/base/<slug>-vbox/<version>/<prefix>-<version>.ova

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/base.env"

BASE_QCOW2="${BASE_QCOW2:?set BASE_QCOW2 to the stage-1 qcow2 path}"
VERSION="${BASE_VERSION:-$(date +%F)}"
[[ -f "${BASE_QCOW2}" ]] || { echo "ERROR: BASE_QCOW2 not found: ${BASE_QCOW2}" >&2; exit 1; }
command -v VBoxManage >/dev/null 2>&1 || { echo "ERROR: VBoxManage not found (install VirtualBox 7.1+ for arm64)" >&2; exit 1; }

OUT_DIR="${PACKER_DIR}/output/base/${BASE_SLUG}-vbox/${VERSION}"
OVA="${OUT_DIR}/${IMAGE_NAME_PREFIX}-${VERSION}.ova"
VM_NAME="alarm-ova-export-${VERSION}"
WORK_DIR="$(mktemp -d -t alarm-ova-XXXXXX)"
mkdir -p "${OUT_DIR}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
cleanup() {
  VBoxManage unregistervm "${VM_NAME}" --delete 2>/dev/null || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# 1. qcow2 → VMDK (VirtualBox-consumable, streamOptimized for a compact OVA).
log "converting qcow2 → VMDK"
VMDK="${WORK_DIR}/${IMAGE_NAME_PREFIX}-${VERSION}.vmdk"
qemu-img convert -O vmdk -o subformat=streamOptimized "${BASE_QCOW2}" "${VMDK}"

# 2. Build a throwaway arm64 VM around the disk.
#    These flags mirror the arm64 wiring documented in the Ubuntu VBox source
#    (armv8virtual chipset, USB HID, virtio storage, EFI, ramfb graphics).
log "creating arm64 VBox VM ${VM_NAME}"
VBoxManage createvm --name "${VM_NAME}" --platform-architecture arm --ostype "Linux_arm64" --register
VBoxManage modifyvm "${VM_NAME}" \
  --chipset armv8virtual \
  --firmware efi \
  --memory "${BUILD_MEMORY_MB}" --cpus "${BUILD_CPUS}" \
  --usb-xhci on --keyboard usb --mouse usb \
  --graphicscontroller qemuramfb \
  --nic1 nat

# 3. Attach the disk over virtio (no IDE on armv8virtual).
VBoxManage storagectl "${VM_NAME}" --name "virtio" --add virtio-scsi --controller VirtIOSCSI --bootable on
VBoxManage storageattach "${VM_NAME}" --storagectl "virtio" --port 0 --device 0 --type hdd --medium "${VMDK}"

# 4. Export .ova.
log "exporting → ${OVA}"
rm -f "${OVA}"
VBoxManage export "${VM_NAME}" --output "${OVA}" --ovf20

# latest/ symlinks (parity with the qemu tree).
VBOX_ROOT="${PACKER_DIR}/output/base/${BASE_SLUG}-vbox"
rm -rf "${VBOX_ROOT}/latest"
ln -sfn "../${VERSION}" "${VBOX_ROOT}/latest"
ln -sfn "${IMAGE_NAME_PREFIX}-${VERSION}.ova" "${OUT_DIR}/${IMAGE_NAME_PREFIX}-latest.ova"

log "VirtualBox base .ova ready: ${OVA}"
