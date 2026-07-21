// archlinux (nthedao personal line) — Arch Linux ARM (ALARM) aarch64 box.
//
// STAGE 2 of the two-stage build. Does NOT install the OS — it boots the qcow2 /
// .ova produced by STAGE 1 (scripts/rootfs-bootstrap/bootstrap-base.sh, which lays down
// the ALARM aarch64 rootfs since Arch has no aarch64 installer ISO) and:
//   1. `pacman -Syu` to pull the rolling release fully current at box time,
//   2. installs a small set of box-friendly packages + trims the pacman cache,
//   3. packages the result into vagrant boxes (libvirt/qemu + virtualbox).
//
// WHY NO ANSIBLE (unlike the Ubuntu lines):
//   playbooks/packer-bake.yml is an apt-based Ubuntu CIS role — it does not apply
//   to Arch. This line is the lightweight personal-lab box the user wanted after
//   finding the Ubuntu base heavy to bake. Provisioning is a small shell block;
//   a CIS-for-Arch role is a documented follow-up (see docs/archlinux-arm64-runbook.md).
//
// Build:
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh archlinux qemu        # qcow2 + box
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh archlinux virtualbox  # ova + box
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh archlinux all         # both
// (STAGE=base runs the bootstrap script; STAGE=all does base then this.)
//
// Output:
//   qemu:       output/nthedao/arm64/qemu/<image_name_prefix>/<image_version>/<image_name_prefix>-<image_version>.{qcow2,box}
//   virtualbox: output/nthedao/arm64/virtualbox/<image_name_prefix>/<image_version>/<image_name_prefix>-<image_version>.{ova,box}
//
// SSH key contract: STAGE 1 baked keys/packer_ed25519.pub into ~packer/.ssh/
// authorized_keys. This stage authenticates with the matching private key.
// Regenerate the keypair → re-bake the base.

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    qemu       = { source = "github.com/hashicorp/qemu", version = "~> 1.1" }
    virtualbox = { source = "github.com/hashicorp/virtualbox", version = "~> 1.0" }
    vagrant    = { source = "github.com/hashicorp/vagrant", version = "~> 1.1" }
  }
}

// ---------- variables ----------

variable "tenant" { type = string }
variable "ssh_username" { type = string }
variable "ssh_timeout" { type = string }
variable "image_version" { type = string }
variable "image_name_prefix" { type = string }
variable "output_base_dir" { type = string }
variable "build_cpus" { type = number }
variable "build_memory" { type = number }

// Extra pacman packages to bake into the box (space-separated). Empty = none.
variable "extra_packages" {
  type    = string
  default = ""
}

// disk_size_mb is provided by common.pkrvars.hcl; declared (unused) because packer
// rejects a var-file that sets an undeclared variable. Disk size is fixed by the
// stage-1 base image.
variable "disk_size_mb" {
  type        = number
  description = "Inherited from common.pkrvars.hcl; unused at stage 2 (disk laid out by stage 1)."
}

variable "qemu_efi_firmware" {
  type    = string
  default = "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
}

variable "qemu_efi_firmware_vars" {
  type    = string
  default = "/opt/homebrew/share/qemu/edk2-arm-vars.fd"
}

variable "ssh_private_key_file" {
  type        = string
  description = "Bake-time SSH private key; its public half was baked into the base at stage 1."
}

variable "base_image_path" {
  type        = string
  default     = ""
  description = "qcow2 from stage 1's qemu bootstrap. Empty is fine for virtualbox-only builds (-only filtered)."
}

variable "base_image_ova_path" {
  type        = string
  default     = ""
  description = "OVA from stage 1's VirtualBox base (qcow2-to-ova.sh). Empty is fine for qemu-only builds."
}

// ---------- locals ----------

locals {
  // Keyed by image_name_prefix so an org with >1 box (nthedao ships both
  // ubuntu2404 and archlinux) doesn't collide on a shared version dir — packer
  // refuses a pre-existing output_directory, and manifest.json would clash.
  output_dir_qemu       = "${var.output_base_dir}/${var.tenant}/arm64/qemu/${var.image_name_prefix}/${var.image_version}"
  output_dir_virtualbox = "${var.output_base_dir}/${var.tenant}/arm64/virtualbox/${var.image_name_prefix}/${var.image_version}"

  // Shared provisioning steps (run identically against both sources).
  //   - Full upgrade (rolling release → current at box time).
  //   - Ensure box essentials present (idempotent; base already has most).
  //   - Optional extra packages.
  //   - Trim pacman cache so the box isn't bloated by downloaded packages.
  //   - Blank machine-id so every `vagrant up` clone gets a fresh identity.
  // sudo -S is used for parity with the Ubuntu lines; the packer user has
  // NOPASSWD sudo so the echoed string is simply ignored.
  provision_inline = [
    "set -e",
    "echo '${var.ssh_username}' | sudo -S pacman -Syu --noconfirm",
    "echo '${var.ssh_username}' | sudo -S pacman -S --noconfirm --needed openssh sudo qemu-guest-agent",
    "if [ -n '${var.extra_packages}' ]; then echo '${var.ssh_username}' | sudo -S pacman -S --noconfirm --needed ${var.extra_packages}; fi",
    "echo '${var.ssh_username}' | sudo -S pacman -Scc --noconfirm",
    "echo '${var.ssh_username}' | sudo -S truncate -s 0 /etc/machine-id",
    "echo '${var.ssh_username}' | sudo -S sh -c 'rm -f /var/lib/dbus/machine-id; ln -sf /etc/machine-id /var/lib/dbus/machine-id'",
  ]
}

// ---------- sources ----------

// qemu: boot the stage-1 qcow2 directly (disk_image = true → iso_url is a bootable
// disk, not an installer). Same aarch64 + hvf + EFI knobs as the Ubuntu lines so the
// image boots under the exact conditions it was built for.
source "qemu" "archlinux-arm64" {
  iso_url      = var.base_image_path
  iso_checksum = "none"
  disk_image   = true

  cpus              = var.build_cpus
  memory            = var.build_memory
  format            = "qcow2"
  qemu_binary       = "qemu-system-aarch64"
  accelerator       = "hvf"
  machine_type      = "virt"
  cpu_model         = "host"
  efi_boot          = true
  efi_firmware_code = var.qemu_efi_firmware
  efi_firmware_vars = var.qemu_efi_firmware_vars

  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout
  // Arch's packer user has NOPASSWD sudo; -S password is ignored but kept for parity.
  shutdown_command = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"

  output_directory = local.output_dir_qemu
  vm_name          = "${var.image_name_prefix}-${var.image_version}.qcow2"
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"
  vnc_bind_address = "127.0.0.1"
  vnc_port_min     = 5900
  vnc_port_max     = 5900

  qemuargs = [
    ["-boot", "strict=off"],
    ["-machine", "type=virt,accel=hvf,highmem=on"],
    ["-device", "virtio-net,netdev=user.0"],
    // virtio-rng: feed host entropy to the guest. Headless aarch64 VMs have no
    // trusted HW RNG, so sshd host-key gen + KEX block on entropy and packer's
    // SSH stalls "timed out during banner exchange". ALARM hit this hard (no
    // haveged, keys generated on first boot); the stage-1 builder already uses it.
    ["-device", "virtio-rng-pci"],
    ["-device", "qemu-xhci"],
    ["-device", "usb-kbd"],
    ["-device", "usb-tablet"],
    ["-device", "ramfb"],
    ["-device", "virtio-gpu-pci"],
  ]
}

// virtualbox-ovf: import the stage-1 .ova (from qcow2-to-ova.sh), provision, re-export.
// EXPERIMENTAL — depends on the VBox arm64 base .ova actually booting (see runbook).
source "virtualbox-ovf" "archlinux-arm64" {
  source_path = var.base_image_ova_path
  checksum    = "none"

  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout
  shutdown_command     = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"

  output_directory = local.output_dir_virtualbox
  vm_name          = "${var.image_name_prefix}-${var.image_version}"
  format           = "ova"
  headless         = true

  // No arm64 Guest Additions — same disable as the Ubuntu lines.
  guest_additions_mode = "disable"
}

// ---------- build ----------

build {
  name = "archlinux-arm64"
  sources = [
    "source.qemu.archlinux-arm64",
    "source.virtualbox-ovf.archlinux-arm64",
  ]

  provisioner "shell" {
    inline = local.provision_inline
  }

  // ----- Vagrant box (virtualbox source) -----
  post-processor "vagrant" {
    only                = ["virtualbox-ovf.archlinux-arm64"]
    output              = "${local.output_dir_virtualbox}/${var.image_name_prefix}-${var.image_version}.box"
    keep_input_artifact = true
    compression_level   = 6
  }

  // ----- Vagrant box (qemu source) -----
  // Hand-assembled libvirt-format box for the vagrant-qemu plugin (Packer's stock
  // vagrant PP can't emit qemu boxes). Identical mechanism to the nthedao Ubuntu
  // line — metadata.json provider MUST be "libvirt", and efivars.fd (bake-time
  // NVRAM, written by the qemu builder) must be bundled.
  post-processor "shell-local" {
    only           = ["qemu.archlinux-arm64"]
    inline_shebang = "/bin/bash -euo pipefail"
    environment_vars = [
      "OUTPUT_DIR=${local.output_dir_qemu}",
      "BOX_NAME=${var.image_name_prefix}-${var.image_version}.box",
      "QCOW2_NAME=${var.image_name_prefix}-${var.image_version}.qcow2",
      // box-vagrantfile.qemu.rb is shared, one level up in templates/.
      // abspath(): the shell-local script `cd`s into $OUTPUT_DIR before using
      // this, so a relative path would break the later `cp`. Absolute survives.
      "VAGRANTFILE_TEMPLATE=${abspath("${path.root}/../box-vagrantfile.qemu.rb")}",
    ]
    inline = [
      "set -x",
      "test -f \"$VAGRANTFILE_TEMPLATE\" || { echo \"missing $VAGRANTFILE_TEMPLATE\" >&2; exit 1; }",
      "cd \"$OUTPUT_DIR\"",
      "test -f \"$QCOW2_NAME\" || { echo \"missing qcow2 in $OUTPUT_DIR: $QCOW2_NAME\" >&2; exit 1; }",
      "test -f efivars.fd || { echo \"missing efivars.fd in $OUTPUT_DIR — bake-time NVRAM was not preserved\" >&2; exit 1; }",
      "VSIZE_GB=$(qemu-img info \"$QCOW2_NAME\" | awk '/virtual size:/{print $3; exit}')",
      "test -n \"$VSIZE_GB\" || { echo 'failed to parse virtual size from qemu-img info' >&2; exit 1; }",
      "stage=$(mktemp -d -t vagrant-qemu-box-XXXXXX)",
      "trap 'rm -rf \"$stage\"' EXIT",
      "cp \"$QCOW2_NAME\" \"$stage/box.img\"",
      "cp efivars.fd \"$stage/efivars.fd\"",
      "printf '{\"provider\":\"libvirt\",\"format\":\"qcow2\",\"architecture\":\"arm64\",\"virtual_size\":%d}\\n' \"$VSIZE_GB\" > \"$stage/metadata.json\"",
      "cp \"$VAGRANTFILE_TEMPLATE\" \"$stage/Vagrantfile\"",
      "tar -czf \"$BOX_NAME\" -C \"$stage\" metadata.json Vagrantfile box.img efivars.fd",
      "ls -lh \"$BOX_NAME\"",
      "tar -tzf \"$BOX_NAME\"",
    ]
  }

  // ----- Manifests (one per source) -----
  post-processor "manifest" {
    only       = ["qemu.archlinux-arm64"]
    output     = "${local.output_dir_qemu}/manifest.json"
    strip_path = true
    custom_data = {
      stage           = "box"
      tenant          = var.tenant
      provider        = "qemu"
      os              = "archlinux-arm64"
      image_version   = var.image_version
      arch            = "arm64"
      base_image_path = var.base_image_path
    }
  }

  post-processor "manifest" {
    only       = ["virtualbox-ovf.archlinux-arm64"]
    output     = "${local.output_dir_virtualbox}/manifest.json"
    strip_path = true
    custom_data = {
      stage               = "box"
      tenant              = var.tenant
      provider            = "virtualbox"
      os                  = "archlinux-arm64"
      image_version       = var.image_version
      arch                = "arm64"
      base_image_ova_path = var.base_image_ova_path
    }
  }
}
