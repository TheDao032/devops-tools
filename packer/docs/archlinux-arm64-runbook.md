# Arch Linux ARM (aarch64) image line — runbook

Lightweight, fast-to-bake alternative to the Ubuntu arm64 lines for the personal
Apple-Silicon k3s lab. Publishes as `nthedao2705/archlinux-arm64`.

> **Status: SCAFFOLDED, NOT YET BAKED.** All files are wired and `packer validate`
> passes, but no image has been produced on real hardware yet. Treat the first run
> as a bring-up: expect to iterate. The **qemu/libvirt** path is primary; the
> **VirtualBox** path is EXPERIMENTAL (see caveats).

---

## Why this line is different from Ubuntu

Mainline Arch is x86_64-only. On aarch64 the distro is **Arch Linux ARM (ALARM)**,
which ships a **rootfs tarball** — there is **no autoinstall installer ISO** like
Ubuntu's subiquity. So the usual "boot ISO + Packer `boot_command`" stage 1 does
not exist here.

Instead the two stages are:

| Stage | Ubuntu lines | Arch line |
|---|---|---|
| **1 — base** | Packer boots installer ISO, subiquity autoinstall → qcow2/ova | **`scripts/rootfs-bootstrap/bootstrap-base.sh`** (shell): boots a throwaway Ubuntu cloud-image builder, lays the ALARM tarball onto a blank disk, chroots in, installs kernel + GRUB(EFI) → qcow2/ova |
| **2 — box** | Packer boots base, runs the CIS ansible role, packages box | **`templates/nthedao/archlinux-arm64.pkr.hcl`** (Packer): boots base, `pacman -Syu` + essentials, packages box |

Stage 1 config lives in **`scripts/rootfs-bootstrap/base.env`** (shell), NOT a `.pkrvars.hcl`,
because it isn't a Packer build. Stage 2 config is
**`variables/nthedao/archlinux-arm64.pkrvars.hcl`**.

---

## Host prerequisites

Already present on the build Mac (verified): `qemu-system-aarch64`, `qemu-img`,
`hdiutil`, `newfs_msdos`, edk2 firmware at `/opt/homebrew/share/qemu/`. VirtualBox
(`VBoxManage`) only needed for the `virtualbox` provider.

The first bootstrap downloads (and caches under `~/iso-cache/`):
- `ArchLinuxARM-aarch64-latest.tar.gz` (~600 MB) — verified against its published `.md5`.
- `ubuntu-22.04-server-cloudimg-arm64.img` (~700 MB) — the throwaway builder.

---

## Build

```bash
cd devops-tools/packer

# Full run: bootstrap the base, then build + package the box (qemu/libvirt).
ARCH=arm64 STAGE=all ./scripts/build.sh archlinux qemu

# Or step by step:
ARCH=arm64 STAGE=base     ./scripts/build.sh archlinux qemu          # stage 1 (bootstrap script)
ARCH=arm64 STAGE=hardened ./scripts/build.sh archlinux qemu 2026-07-18.1  # stage 2 (packer)

# VirtualBox too (EXPERIMENTAL): also emits the .ova base + a vbox .box.
ARCH=arm64 STAGE=all ./scripts/build.sh archlinux all
```

Stage 1 can also be run directly (handy while iterating on the installer):
```bash
BASE_VERSION=2026-07-18 PROVIDER=qemu ./scripts/rootfs-bootstrap/bootstrap-base.sh
```

### Outputs
```
output/base/archlinux-arm64/<ver>/archlinux-arm64-base-<ver>.qcow2     # stage-1 qemu base
output/base/archlinux-arm64-vbox/<ver>/archlinux-arm64-base-<ver>.ova  # stage-1 vbox base (experimental)
output/nthedao/arm64/qemu/<ver>/archlinux-arm64-<ver>.{qcow2,box}    # stage-2 qemu box
output/nthedao/arm64/virtualbox/<ver>/archlinux-arm64-<ver>.{ova,box}
```

---

## How stage 1 works (the interesting part)

`bootstrap-base.sh`:
1. Fetches + md5-verifies the ALARM tarball and the Ubuntu cloud image.
2. Renders a NoCloud seed ISO (`hdiutil`), injecting `keys/packer_ed25519.pub`.
3. Boots the Ubuntu cloud image under qemu/hvf as an **ephemeral overlay** (never
   mutated), with a **blank target qcow2** attached as the 2nd virtio disk and
   `virtio-rng` for pacman-key entropy.
4. SSHes in and runs **`install-alarm.sh`** inside the builder, which:
   partitions the target (GPT: ESP + root, labels `ESP`/`ROOT`) → extracts the
   ALARM rootfs → native-chroots (same arch, no emulation) → `pacman-key` init +
   `pacman -Syu` → installs `linux-aarch64`, `grub`+`efibootmgr` (**`--removable`**
   → `BOOTAA64.EFI`, boots without NVRAM entries), `openssh`, `sudo`,
   `qemu-guest-agent` → bakes the `packer` user + authorized_keys + NOPASSWD
   sudo → `systemd-networkd` DHCP → enables sshd.
5. Powers off, compacts the target with `qemu-img convert`, places it under
   `output/base/…`.

Filesystems are addressed by **LABEL** everywhere (fstab, GRUB `root=LABEL=ROOT`)
so the builder's `/dev/vdb` → final image's `/dev/vda` rename is a non-issue.

---

## Caveats / follow-ups

- **First-bake gotchas to expect:** `pacman-key --populate` occasionally needs the
  refreshed `archlinuxarm-keyring` (the tarball's can be stale) — the `pacman -Syu`
  ordering handles the common case; if key errors persist, re-run stage 1 (the
  builder is throwaway). Watch `serial.log` in the temp workdir on a hang.
- **VirtualBox is EXPERIMENTAL.** `scripts/rootfs-bootstrap/qcow2-to-ova.sh` builds the
  base `.ova` via `VBoxManage` arm64 flags (`--platform-architecture arm`,
  `armv8virtual`), which vary by VBox point release. If it errors, check
  `VBoxManage --version` (need 7.1+) and adjust flags. The qemu/libvirt path does
  not depend on any of this.
- **No CIS hardening yet.** Unlike the Ubuntu lines, stage 2 is a plain shell
  provisioner (`pacman -Syu` + essentials), not the ansible compliance role
  (that role is apt-based). A CIS-for-Arch role is a future addition; add packages
  via `extra_packages` in the stage-2 pkrvars meanwhile.
- **"Latest" = rolling.** The tarball is a point-in-time snapshot; stage 1's
  `pacman -Syu` pulls it current, and stage 2 does so again at box time.

---

## Consuming the box in the k3s lab

After a successful qemu build:
```bash
vagrant plugin install vagrant-qemu   # once
vagrant box add nthedao2705/archlinux-arm64 \
  ./output/nthedao/arm64/qemu/<ver>/archlinux-arm64-<ver>.box \
  --provider libvirt --architecture arm64
```
Then point `vagrant/vagrant-files/k3s/config.yaml`'s `box:` at
`nthedao2705/archlinux-arm64` (currently it consumes the Ubuntu box). Login user
is `packer`.
