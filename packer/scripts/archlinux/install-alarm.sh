#!/usr/bin/env bash
# install-alarm.sh — the heart of the Arch Linux ARM (ALARM) aarch64 STAGE-1 bake.
#
# Runs *inside the throwaway builder VM* (an Ubuntu arm64 cloud image), NOT on the
# macOS host. scripts/archlinux/bootstrap-base.sh scp's this file into the builder
# and executes it over SSH. See that script for how the builder is launched and why
# a builder VM is needed at all (macOS has no ext4/loop tooling; the ALARM tarball
# has to be laid onto a real Linux block device and chrooted into to install a
# bootloader — that must happen on a Linux host of the SAME arch, so we do it in an
# ephemeral aarch64 Ubuntu guest under hvf).
#
# WHY A TARBALL, NOT AN ISO:
#   Mainline Arch is x86_64-only. On aarch64 the distro is Arch Linux ARM (ALARM),
#   which ships as a rootfs tarball (ArchLinuxARM-aarch64-latest.tar.gz) — there is
#   no autoinstall ISO like Ubuntu's subiquity. So "install" here means: partition a
#   blank disk, extract the rootfs, chroot in, and install a kernel + EFI bootloader
#   ourselves. That is exactly what this script does.
#
# CONTRACT WITH THE HOST SCRIPT (bootstrap-base.sh):
#   - The blank target disk is attached to the builder as the SECOND virtio disk.
#     We resolve it by "the virtio disk that is NOT the one carrying /" rather than
#     hard-coding /dev/vdb, so the script is robust to device enumeration order.
#   - The ALARM tarball is present in the builder at $TARBALL (default /root/alarm.tar.gz).
#   - The bake-time SSH public key is present at $PUBKEY_FILE (default /root/packer.pub);
#     it is injected into the baked image's ~packer/.ssh/authorized_keys so STAGE 2
#     (Packer) can SSH in with the matching private key — same key contract as the
#     Ubuntu base bake.
#
# POSITION-INDEPENDENCE:
#   In the builder the target is the 2nd disk (e.g. /dev/vdb); in the FINAL baked
#   qcow2 it is the 1st and only disk (/dev/vda). To make fstab + GRUB survive that
#   rename we address filesystems by LABEL (ESP / ROOT), never by /dev/vdX or by a
#   UUID that we'd have to re-read. LABEL=ROOT resolves correctly under either name.

set -euo pipefail

# ---- knobs (overridable via env from the host script) ----------------------
TARBALL="${TARBALL:-/root/alarm.tar.gz}"       # ALARM aarch64 rootfs tarball
PUBKEY_FILE="${PUBKEY_FILE:-/root/packer.pub}"  # bake-time SSH public key
SSH_USERNAME="${SSH_USERNAME:-packer}"          # bootstrap user Packer SSHes in as
ESP_SIZE_MIB="${ESP_SIZE_MIB:-512}"             # EFI System Partition size
MNT="/mnt/alarm"                                # chroot mountpoint

log() { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root inside the builder"
[[ -f "$TARBALL" ]] || die "ALARM tarball not found at $TARBALL"
[[ -f "$PUBKEY_FILE" ]] || die "SSH pubkey not found at $PUBKEY_FILE"

# ---- 0. builder-side prerequisites -----------------------------------------
# The Ubuntu cloud image is minimal. We need partitioning + filesystem tooling.
# arch-install-scripts gives us `arch-chroot` (handles the bind mounts for us),
# but we fall back to a manual chroot if it is unavailable.
log "installing builder-side tools (parted, dosfstools, e2fsprogs, arch-install-scripts)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq parted dosfstools e2fsprogs arch-install-scripts >/dev/null

# ---- 1. resolve the target disk --------------------------------------------
# The root filesystem's backing disk is the builder's own OS disk — never touch it.
# The target is the other whole-disk virtio device.
ROOT_SRC="$(findmnt -no SOURCE / || true)"                 # e.g. /dev/vda1
ROOT_DISK="/dev/$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null || true)"
log "builder root is on ${ROOT_SRC} (disk ${ROOT_DISK}) — will not be touched"

TARGET=""
for d in /dev/vd? /dev/sd?; do
  [[ -b "$d" ]] || continue
  [[ "$d" == "$ROOT_DISK" ]] && continue
  TARGET="$d"
  break
done
[[ -n "$TARGET" ]] || die "could not find a blank target disk (expected a 2nd virtio disk)"
log "target disk = ${TARGET}"

# Refuse to run if the target already has partitions we didn't make, unless the
# host script explicitly set FORCE=1 (blank qcow2 is the normal case → no parts).
if lsblk -no NAME "$TARGET" | tail -n +2 | grep -q . && [[ "${FORCE:-0}" != "1" ]]; then
  die "${TARGET} already has partitions; set FORCE=1 to wipe (normally the target is a fresh blank qcow2)"
fi

# ---- 2. partition: GPT, ESP (FAT32) + root (ext4) --------------------------
log "partitioning ${TARGET} (GPT: ESP ${ESP_SIZE_MIB}MiB + root)"
wipefs -a "$TARGET" || true
parted -s "$TARGET" mklabel gpt
parted -s "$TARGET" mkpart ESP fat32 1MiB "$((ESP_SIZE_MIB + 1))MiB"
parted -s "$TARGET" set 1 esp on
parted -s "$TARGET" mkpart ROOT ext4 "$((ESP_SIZE_MIB + 1))MiB" 100%
# Re-read the partition table and wait for udev to create the nodes.
partprobe "$TARGET"; sleep 2

# Resolve child partition nodes (handles both /dev/vdb1 and /dev/nvme0n1p1 styles).
ESP_PART="$(lsblk -rno NAME "$TARGET" | sed -n '2p')"; ESP_PART="/dev/${ESP_PART}"
ROOT_PART="$(lsblk -rno NAME "$TARGET" | sed -n '3p')"; ROOT_PART="/dev/${ROOT_PART}"
[[ -b "$ESP_PART" && -b "$ROOT_PART" ]] || die "partition nodes not found ($ESP_PART / $ROOT_PART)"

log "formatting: ${ESP_PART} = FAT32 (label ESP), ${ROOT_PART} = ext4 (label ROOT)"
mkfs.fat -F32 -n ESP "$ESP_PART"
mkfs.ext4 -F -L ROOT "$ROOT_PART"

# ---- 3. extract the ALARM rootfs -------------------------------------------
log "mounting ${ROOT_PART} at ${MNT} and extracting ALARM rootfs"
mkdir -p "$MNT"
mount "$ROOT_PART" "$MNT"
mkdir -p "$MNT/boot/efi"
mount "$ESP_PART" "$MNT/boot/efi"

# bsdtar preserves the numeric owners/xattrs in the ALARM tarball. arch-install-scripts
# pulls in libarchive-tools on Ubuntu; prefer bsdtar, fall back to GNU tar.
if command -v bsdtar >/dev/null 2>&1; then
  bsdtar -xpf "$TARBALL" -C "$MNT"
else
  tar -xpf "$TARBALL" -C "$MNT" --numeric-owner
fi
sync

# ---- 4. fstab (by LABEL, so vda/vdb rename is a non-issue) ------------------
log "writing /etc/fstab (LABEL-based)"
cat > "$MNT/etc/fstab" <<'FSTAB'
# <file system>   <dir>       <type>  <options>            <dump> <pass>
LABEL=ROOT        /           ext4    rw,relatime          0      1
LABEL=ESP         /boot/efi   vfat    rw,fmask=0137,dmask=0027,noatime 0 2
FSTAB

# ---- 5. chroot: keyring, update, kernel, bootloader, config ----------------
# arch-chroot sets up /dev /proc /sys /run bind mounts and a resolv.conf for us.
# Everything below runs as aarch64 Arch binaries under the aarch64 builder — native,
# no qemu-user emulation. We drive it via a heredoc script executed in the chroot.
log "configuring inside chroot (keyring, pacman -Syu, kernel, GRUB, users, network)"

# Give pacman-key enough entropy. The builder qemu exposes virtio-rng (see host
# script) so /dev/random is well-seeded; haveged is a belt-and-braces fallback.
cat > "$MNT/root/chroot-setup.sh" <<CHROOT
set -euo pipefail

# ALARM ships an expired-by-default keyring on the "latest" tarball often enough
# that init+populate is mandatory before any pacman transaction.
pacman-key --init
pacman-key --populate archlinuxarm

# Full system upgrade first (rolling release — the tarball is a point-in-time
# snapshot; this pulls it up to genuine "latest").
pacman -Syu --noconfirm

# Core packages for a bootable, SSH-able, hypervisor-friendly image.
#   linux-aarch64        — kernel + modules (ALARM's aarch64 kernel)
#   mkinitcpio           — initramfs (pulled by linux-aarch64, explicit for clarity)
#   grub efibootmgr dosfstools — EFI bootloader install
#   openssh sudo         — remote access + privilege for the packer user
#   qemu-guest-agent     — clean shutdown / host integration under qemu
#   cloud-init           — optional; enables NoCloud/config-drive on consumers (kept minimal)
#   which vim            — quality-of-life for debugging first boots
pacman -S --noconfirm --needed \\
  linux-aarch64 mkinitcpio \\
  grub efibootmgr dosfstools \\
  openssh sudo \\
  qemu-guest-agent \\
  cloud-init \\
  which vim

# ----- initramfs -----
mkinitcpio -P

# ----- GRUB (EFI, removable path) -----
# --removable writes /boot/efi/EFI/BOOT/BOOTAA64.EFI, the EFI "fallback" path that
# edk2 boots WITHOUT a persisted NVRAM boot entry. Critical for portability: the
# baked qcow2 gets fresh efivars on every boot (Packer stage 2 and the vagrant-qemu
# box both start from clean NVRAM), so relying on an efibootmgr entry would brick
# boot. The removable path always works.
grub-install --target=arm64-efi --efi-directory=/boot/efi --removable --boot-directory=/boot --recheck

# Boot by LABEL so the vda(final)/vdb(builder) rename never matters.
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="root=LABEL=ROOT rw"|' /etc/default/grub || \\
  echo 'GRUB_CMDLINE_LINUX="root=LABEL=ROOT rw"' >> /etc/default/grub
# os-prober is pointless in a single-OS image and just noisy.
grep -q '^GRUB_DISABLE_OS_PROBER' /etc/default/grub || echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# ----- locale / hostname / clock -----
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'archlinux-arm64' > /etc/hostname
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc 2>/dev/null || true

# ----- networking: systemd-networkd DHCP on the PCI virtio NIC -----
# The vagrant-qemu box wires virtio-net-PCI → predictable enpXsY names → match en*.
# (See templates/box-vagrantfile.qemu.rb for why PCI, not mmio.)
cat > /etc/systemd/network/20-wired.network <<'NET'
[Match]
Name=en*

[Network]
DHCP=yes
NET
systemctl enable systemd-networkd systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# ----- services -----
systemctl enable sshd qemu-guest-agent
# cloud-init left INSTALLED but its services enabled so a NoCloud seed works on
# consumers; harmless when no seed is present (it no-ops).
systemctl enable cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true

# ----- bootstrap user (Packer's SSH contract) -----
# Match the Ubuntu base convention: a 'packer' user, key-authed, passwordless sudo.
# ALARM's default 'alarm' user + 'root:root' are removed/locked so the image isn't
# shipped with a well-known password.
id ${SSH_USERNAME} &>/dev/null || useradd -m -G wheel -s /bin/bash ${SSH_USERNAME}
# Passwordless sudo for the wheel group (Packer provisions with sudo -S).
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-packer
chmod 0440 /etc/sudoers.d/99-packer
install -d -m 0700 -o ${SSH_USERNAME} -g ${SSH_USERNAME} /home/${SSH_USERNAME}/.ssh
CHROOT

# Append the authorized_keys write using the real pubkey contents (kept out of the
# heredoc above so the key text can't collide with heredoc quoting).
{
  printf 'install -m 0600 -o %s -g %s /dev/stdin /home/%s/.ssh/authorized_keys <<'"'"'KEY'"'"'\n' \
    "$SSH_USERNAME" "$SSH_USERNAME" "$SSH_USERNAME"
  cat "$PUBKEY_FILE"
  printf 'KEY\n'
  # Lock the well-known ALARM defaults.
  printf 'passwd -l root || true\n'
  printf 'userdel -r alarm 2>/dev/null || true\n'
} >> "$MNT/root/chroot-setup.sh"

chmod +x "$MNT/root/chroot-setup.sh"

if command -v arch-chroot >/dev/null 2>&1; then
  arch-chroot "$MNT" /root/chroot-setup.sh
else
  # Manual bind-mount fallback.
  for fs in dev proc sys run; do mount --rbind "/$fs" "$MNT/$fs"; done
  cp -f /etc/resolv.conf "$MNT/etc/resolv.conf"
  chroot "$MNT" /root/chroot-setup.sh
  for fs in run sys proc dev; do umount -R "$MNT/$fs" 2>/dev/null || true; done
fi

# ---- 6. teardown -----------------------------------------------------------
rm -f "$MNT/root/chroot-setup.sh"
sync
umount -R "$MNT"
log "ALARM aarch64 base install complete on ${TARGET}. Host script will now detach + keep the qcow2."
