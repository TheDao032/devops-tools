#!/usr/bin/env bash
# bootstrap-base.sh — STAGE 1 of the Arch Linux ARM (ALARM) aarch64 image line.
#
# Produces a clean, bootable, SSH-ready ALARM aarch64 base qcow2 at:
#   output/base/archlinux-arm64/<version>/archlinux-arm64-base-<version>.qcow2
#
# WHY THIS IS A SCRIPT, NOT A PACKER TEMPLATE:
#   Ubuntu stage 1 boots an installer ISO and drives subiquity via Packer's
#   boot_command. ALARM has NO installer ISO — it's a rootfs tarball. So stage 1
#   here is: boot a throwaway aarch64 Linux builder, lay the tarball onto a blank
#   disk, chroot in, install a kernel + EFI bootloader. That's plain host tooling
#   (qemu + ssh), so it lives as a script. Stage 2 (customize + package into a box)
#   IS Packer — see templates/nthedao/archlinux-arm64.pkr.hcl.
#
#   builder = Ubuntu arm64 CLOUD IMAGE (a ready qcow2, boots in seconds, no install)
#   installer logic = scripts/archlinux/install-alarm.sh (runs inside the builder)
#
# USAGE:
#   ./scripts/archlinux/bootstrap-base.sh [version]      # version defaults to today
#   BASE_VERSION=2026-07-18 PROVIDER=all ./scripts/archlinux/bootstrap-base.sh
#   (normally invoked by scripts/build.sh for STAGE=base on the archlinux line)
#
# ENV: see scripts/archlinux/base.env for every knob. PROVIDER=virtualbox|all also
#      emits a VirtualBox .ova base via scripts/archlinux/qcow2-to-ova.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/base.env"

VERSION="${1:-${BASE_VERSION:-$(date +%F)}}"
PROVIDER="${PROVIDER:-qemu}"
CACHE_DIR="${CACHE_DIR:-${HOME}/iso-cache}"
OUT_DIR="${PACKER_DIR}/output/base/${BASE_SLUG}/${VERSION}"
WORK_DIR="$(mktemp -d -t alarm-bootstrap-XXXXXX)"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

QEMU_PID=""
cleanup() {
  [[ -n "${QEMU_PID}" ]] && kill "${QEMU_PID}" 2>/dev/null || true
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# ── prereqs ─────────────────────────────────────────────────────────────────
for bin in qemu-system-aarch64 qemu-img ssh scp hdiutil curl; do
  command -v "$bin" >/dev/null 2>&1 || die "required tool not found on host: $bin"
done
[[ -f "${QEMU_EFI_CODE}" ]] || die "edk2 firmware code not found: ${QEMU_EFI_CODE} (brew install qemu)"
[[ -f "${QEMU_EFI_VARS}" ]] || die "edk2 firmware vars not found: ${QEMU_EFI_VARS}"

# ── SSH key (same contract + path as scripts/build.sh) ──────────────────────
SSH_KEY="${PACKER_DIR}/keys/packer_ed25519"
if [[ ! -f "${SSH_KEY}" ]]; then
  log "generating SSH keypair at ${SSH_KEY} (matches build.sh)"
  mkdir -p "${PACKER_DIR}/keys"
  ssh-keygen -t ed25519 -C "packer-bake@$(hostname -s)" -f "${SSH_KEY}" -N '' -q
fi
SSH_PUB="$(cat "${SSH_KEY}.pub")"

SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=5 -o LogLevel=ERROR -p "${SSH_HOSTFWD_PORT}")
ssh_builder() { ssh "${SSH_OPTS[@]}" "root@127.0.0.1" "$@"; }
scp_builder() { scp "${SSH_OPTS[@]}" "$@"; }  # caller supplies src + root@127.0.0.1:dst

mkdir -p "${CACHE_DIR}" "${OUT_DIR}"

# ── 1. fetch + verify the ALARM tarball ─────────────────────────────────────
TARBALL_CACHE="${CACHE_DIR}/ArchLinuxARM-aarch64-latest.tar.gz"
log "fetching ALARM aarch64 tarball → ${TARBALL_CACHE}"
curl -fL --retry 3 -o "${TARBALL_CACHE}" "${ALARM_TARBALL_URL}"
if curl -fsL --retry 3 -o "${WORK_DIR}/alarm.md5" "${ALARM_TARBALL_MD5_URL}" 2>/dev/null; then
  EXPECT_MD5="$(awk '{print $1}' "${WORK_DIR}/alarm.md5")"
  ACTUAL_MD5="$(md5 -q "${TARBALL_CACHE}" 2>/dev/null || md5sum "${TARBALL_CACHE}" | awk '{print $1}')"
  [[ "${EXPECT_MD5}" == "${ACTUAL_MD5}" ]] \
    || die "ALARM tarball md5 mismatch: expected ${EXPECT_MD5}, got ${ACTUAL_MD5}"
  log "ALARM tarball md5 verified (${ACTUAL_MD5})"
else
  warn "could not fetch ${ALARM_TARBALL_MD5_URL}; skipping checksum verification"
fi

# ── 2. fetch the Ubuntu cloud-image builder ─────────────────────────────────
CLOUDIMG_CACHE="${CACHE_DIR}/$(basename "${UBUNTU_CLOUDIMG_URL}")"
if [[ ! -f "${CLOUDIMG_CACHE}" ]]; then
  log "fetching Ubuntu arm64 cloud image (builder) → ${CLOUDIMG_CACHE}"
  curl -fL --retry 3 -o "${CLOUDIMG_CACHE}" "${UBUNTU_CLOUDIMG_URL}"
fi

# ── 3. render + build the NoCloud seed ISO ──────────────────────────────────
log "building NoCloud seed (injecting bake-time SSH pubkey)"
SEED_STAGE="${WORK_DIR}/seed"
mkdir -p "${SEED_STAGE}"
awk -v key="${SSH_PUB}" '{ gsub("@@SSH_PUBKEY@@", key); print }' \
  "${SCRIPT_DIR}/seed/user-data.tmpl" > "${SEED_STAGE}/user-data"
cp "${SCRIPT_DIR}/seed/meta-data" "${SEED_STAGE}/meta-data"
SEED_ISO="${WORK_DIR}/seed.iso"
# hdiutil is the no-extra-deps way to make a labeled ISO9660 on macOS. cloud-init's
# NoCloud datasource matches the volume label CIDATA (case-insensitive).
hdiutil makehybrid -quiet -iso -joliet -default-volume-name CIDATA -o "${SEED_ISO}" "${SEED_STAGE}"

# ── 4. prepare disks ────────────────────────────────────────────────────────
log "preparing builder overlay + blank target disk (${TARGET_DISK_SIZE})"
BUILDER_OVERLAY="${WORK_DIR}/builder-overlay.qcow2"
# Never mutate the cached cloud image — use a copy-on-write overlay for this run.
qemu-img create -q -f qcow2 -F qcow2 -b "${CLOUDIMG_CACHE}" "${BUILDER_OVERLAY}"
qemu-img resize -q "${BUILDER_OVERLAY}" +4G   # headroom for apt tooling

TARGET_DISK="${WORK_DIR}/target.qcow2"
qemu-img create -q -f qcow2 "${TARGET_DISK}" "${TARGET_DISK_SIZE}"

# Writable copy of the EFI vars for the builder (pflash needs a writable unit).
BUILDER_EFIVARS="${WORK_DIR}/builder-efivars.fd"
cp "${QEMU_EFI_VARS}" "${BUILDER_EFIVARS}"

# ── 5. boot the builder ─────────────────────────────────────────────────────
log "booting throwaway builder (hvf, headless); serial → ${WORK_DIR}/serial.log"
qemu-system-aarch64 \
  -machine virt,accel=hvf,highmem=on \
  -cpu host -smp "${BUILD_CPUS}" -m "${BUILD_MEMORY_MB}" \
  -drive "if=pflash,format=raw,readonly=on,file=${QEMU_EFI_CODE}" \
  -drive "if=pflash,format=raw,file=${BUILDER_EFIVARS}" \
  -device virtio-rng-pci \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_HOSTFWD_PORT}-:22" \
  -device virtio-net-pci,netdev=net0 \
  -drive "if=virtio,format=qcow2,file=${BUILDER_OVERLAY}" \
  -drive "if=virtio,format=qcow2,file=${TARGET_DISK}" \
  -drive "if=virtio,format=raw,file=${SEED_ISO},media=cdrom" \
  -display none -serial "file:${WORK_DIR}/serial.log" &
QEMU_PID=$!

# ── 6. wait for builder SSH ─────────────────────────────────────────────────
log "waiting for builder SSH on 127.0.0.1:${SSH_HOSTFWD_PORT} (<= ${BUILDER_BOOT_TIMEOUT}s)"
deadline=$(( $(date +%s) + BUILDER_BOOT_TIMEOUT ))
until ssh_builder true 2>/dev/null; do
  kill -0 "${QEMU_PID}" 2>/dev/null || die "builder qemu exited early — see ${WORK_DIR}/serial.log"
  [[ $(date +%s) -lt ${deadline} ]] || { warn "serial tail:"; tail -n 40 "${WORK_DIR}/serial.log" >&2 || true; die "timed out waiting for builder SSH"; }
  sleep 3
done
log "builder is up"

# ── 7. run the installer inside the builder ─────────────────────────────────
log "copying installer + tarball + pubkey into builder"
scp_builder "${SCRIPT_DIR}/install-alarm.sh" "root@127.0.0.1:/root/install-alarm.sh"
scp_builder "${TARBALL_CACHE}"                "root@127.0.0.1:/root/alarm.tar.gz"
scp_builder "${SSH_KEY}.pub"                  "root@127.0.0.1:/root/packer.pub"

log "running install-alarm.sh (partition → extract ALARM → chroot → kernel + GRUB)"
ssh_builder "TARBALL=/root/alarm.tar.gz PUBKEY_FILE=/root/packer.pub \
             SSH_USERNAME='${SSH_USERNAME}' ESP_SIZE_MIB='${ESP_SIZE_MIB}' \
             bash /root/install-alarm.sh"

# ── 8. shut the builder down cleanly ────────────────────────────────────────
log "powering off builder"
ssh_builder "poweroff" 2>/dev/null || true
for _ in $(seq 1 30); do kill -0 "${QEMU_PID}" 2>/dev/null || break; sleep 1; done
kill "${QEMU_PID}" 2>/dev/null || true
QEMU_PID=""

# ── 9. finalize the base qcow2 (compact + place) ────────────────────────────
FINAL_QCOW2="${OUT_DIR}/${IMAGE_NAME_PREFIX}-${VERSION}.qcow2"
log "compacting baked target → ${FINAL_QCOW2}"
qemu-img convert -O qcow2 "${TARGET_DISK}" "${FINAL_QCOW2}"

# latest/ symlinks (build.sh also does this; harmless + convenient for standalone runs).
QEMU_BASE_ROOT="${PACKER_DIR}/output/base/${BASE_SLUG}"
rm -rf "${QEMU_BASE_ROOT}/latest"
ln -sfn "../${VERSION}" "${QEMU_BASE_ROOT}/latest"
ln -sfn "${IMAGE_NAME_PREFIX}-${VERSION}.qcow2" \
  "${OUT_DIR}/${IMAGE_NAME_PREFIX}-latest.qcow2"

qemu-img info "${FINAL_QCOW2}" | sed 's/^/    /'
log "STAGE 1 (qemu) done: ${FINAL_QCOW2}"

# ── 10. optional VirtualBox base .ova ───────────────────────────────────────
if [[ "${PROVIDER}" == "virtualbox" || "${PROVIDER}" == "all" ]]; then
  log "PROVIDER=${PROVIDER} → building VirtualBox .ova base (EXPERIMENTAL, see qcow2-to-ova.sh)"
  BASE_QCOW2="${FINAL_QCOW2}" BASE_VERSION="${VERSION}" \
    "${SCRIPT_DIR}/qcow2-to-ova.sh"
fi

echo
echo "Next: STAGE 2 (customize + package into a vagrant box):"
echo "  ARCH=arm64 STAGE=hardened ./scripts/build.sh archlinux ${PROVIDER} <image_version>"
