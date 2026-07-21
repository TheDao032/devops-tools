// nthedao — Ubuntu 24.04 ARM64 hardened image (CIS-L1, no FIPS).
//
// STAGE 2 of the two-stage build. This template does NOT install the OS — it
// boots the qcow2 produced by stage 1 (templates/_base/ubuntu2404-arm64-base.pkr.hcl)
// and runs the compliance role against it. Iteration cost: ~3 min per ansible
// edit, vs ~12-15 min for a full install+ansible cycle.
//
// Lineage: cloned from templates/bosch/ubuntu2204-arm64-hardened.pkr.hcl. This
// is the personal-lab line: it replaces the old republished
// nthedao2705/ubuntu2204-cisl1-arm64 box (which was the bosch 22.04 image under
// the personal account) with a purpose-built 24.04 image. The k3s-etcd QEMU lab
// (vagrant/vagrant-files/k3s/config.yaml) consumes the published .box.
//
// Build:
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh nthedao qemu        # qcow2 only
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh nthedao virtualbox  # ova + box
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh nthedao all         # both, parallel
// or directly:
//   packer init templates/nthedao/ubuntu2404-arm64-hardened.pkr.hcl
//   packer build \
//     -var-file=variables/common.pkrvars.hcl \
//     -var-file=variables/nthedao/arm64.pkrvars.hcl \
//     -var ssh_private_key_file=keys/packer_ed25519 \
//     -var base_image_path=output/base/ubuntu2404-arm64/<base-ver>/ubuntu2404-arm64-base-<base-ver>.qcow2 \
//     -var base_image_ova_path=output/base/ubuntu2404-arm64-vbox/<base-ver>/ubuntu2404-arm64-base-<base-ver>.ova \
//     -only=qemu.nthedao-ubuntu2404-arm64 \    # or virtualbox-ovf.nthedao-ubuntu2404-arm64
//     templates/nthedao/ubuntu2404-arm64-hardened.pkr.hcl
//
// Output:
//   qemu:       output/nthedao/arm64/qemu/<image_name_prefix>/<image_version>/<image_name_prefix>-<image_version>.qcow2
//   virtualbox: output/nthedao/arm64/virtualbox/<image_name_prefix>/<image_version>/<image_name_prefix>-<image_version>.{ova,box}
//
// SSH key contract:
//   Stage 1 baked the public half of keys/packer_ed25519 into the base image's
//   ~packer/.ssh/authorized_keys via cloud-init. This stage's qemu source uses
//   the matching private key for both packer's own SSH and the ansible
//   provisioner. If you regenerate the keypair, re-bake the base — the old
//   base image's authorized_keys won't accept the new key.
//
// Provider scope (Path D): two sources, each producing qcow2/ova + .box.
//   - qemu             → qcow2  + .box (provider=qemu, vagrant-qemu plugin)
//   - virtualbox-ovf   → ova    + .box (provider=virtualbox)
//   qemu .box is hand-assembled by a shell-local PP (Packer's stock `vagrant`
//   PP does not emit qemu-provider boxes). Both consume stage 1's pre-baked
//   image and run the same ansible compliance role (harden-once contract).

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    qemu       = { source = "github.com/hashicorp/qemu", version = "~> 1.1" }
    ansible    = { source = "github.com/hashicorp/ansible", version = "~> 1.1" }
    virtualbox = { source = "github.com/hashicorp/virtualbox", version = "~> 1.0" }
    vagrant    = { source = "github.com/hashicorp/vagrant", version = "~> 1.1" }
  }
}

// ---------- variables ----------

variable "tenant"             { type = string }
variable "compliance_profile" { type = string }
variable "fips_mode"          { type = string }
variable "ssh_username"       { type = string }
variable "ssh_timeout"        { type = string }
variable "login_banner"       { type = string }
variable "image_version"      { type = string }
variable "image_name_prefix"  { type = string }
variable "output_base_dir"    { type = string }
variable "build_cpus"         { type = number }
variable "build_memory"       { type = number }

// disk_size_mb is set by stage 1; declared here only because common.pkrvars.hcl
// provides it and packer rejects undeclared vars in pkrvars files. Unused in
// this template (the base qcow2 already has its disk laid out).
variable "disk_size_mb" {
  type        = number
  description = "Inherited from common.pkrvars.hcl; not used at stage 2 (disk size is fixed by stage 1's bake)."
}

// EFI firmware — same defaults as stage 1. Stage 2 boots with EFI because the
// base was installed under EFI; switching firmware between stages bricks boot.
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
  description = "Path to the bake-time SSH private key. Must match the key whose pubkey was injected into the base image at stage 1."
}

variable "base_image_path" {
  type        = string
  default     = ""
  description = "Path to the qcow2 produced by stage 1's qemu source. Empty is fine for virtualbox-only builds (filtered via -only)."
}

variable "base_image_ova_path" {
  type        = string
  default     = ""
  description = "Path to the .ova produced by stage 1's virtualbox-iso source. Empty is fine for qemu-only builds (filtered via -only)."
}

// ---------- locals ----------

locals {
  // Keyed by image_name_prefix so an org with >1 box (e.g. nthedao ships both
  // ubuntu2404 and archlinux) doesn't collide on a shared version dir — packer
  // refuses a pre-existing output_directory, and manifest.json would clash.
  output_dir_qemu       = "${var.output_base_dir}/${var.tenant}/arm64/qemu/${var.image_name_prefix}/${var.image_version}"
  output_dir_virtualbox = "${var.output_base_dir}/${var.tenant}/arm64/virtualbox/${var.image_name_prefix}/${var.image_version}"
}

// ---------- source ----------

source "qemu" "nthedao-ubuntu2404-arm64" {
  // disk_image = true → iso_url is a bootable disk, not an installer ISO.
  // No autoinstall/http_directory/boot_command — packer boots the qcow2 and
  // waits for SSH.
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
  ssh_password         = var.ssh_username       // fallback only; key is preferred
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout
  shutdown_command     = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"

  output_directory = local.output_dir_qemu
  vm_name          = "${var.image_name_prefix}-${var.image_version}.qcow2"
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"
  vnc_bind_address = "127.0.0.1"
  vnc_port_min     = 5900
  vnc_port_max     = 5900

  // Same aarch64+hvf qemuargs as stage 1 (the base was installed under these
  // conditions; deviating risks boot-time surprises).
  qemuargs = [
    ["-boot", "strict=off"],
    ["-machine", "type=virt,accel=hvf,highmem=on"],
    ["-device", "virtio-net,netdev=user.0"],
    // virtio-rng: host entropy for the guest — headless aarch64 sshd host-key
    // gen + KEX stall without it ("timed out during banner exchange").
    ["-device", "virtio-rng-pci"],
    ["-device", "qemu-xhci"],
    ["-device", "usb-kbd"],
    ["-device", "usb-tablet"],
    ["-device", "ramfb"],
    ["-device", "virtio-gpu-pci"],
  ]
}

// virtualbox-ovf consumes stage 1's pre-baked .ova (no reinstall). Packer
// imports the OVA, runs the same provisioners as the qemu source, then
// re-exports as .ova for the vagrant post-processor to wrap into a .box.
source "virtualbox-ovf" "nthedao-ubuntu2404-arm64" {
  source_path = var.base_image_ova_path
  // checksum = "none": source_path is our own pipeline output, not a remote
  // download where a checksum would guard against corrupted transfer.
  checksum = "none"

  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_username       // fallback only; key is preferred
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = var.ssh_timeout
  shutdown_command     = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"

  output_directory = local.output_dir_virtualbox
  // No file extension — vbox plugin appends `.ova` when format = "ova".
  vm_name  = "${var.image_name_prefix}-${var.image_version}"
  format   = "ova"
  headless = true

  // Guest Additions has no working arm64 build — same disable as stage 1.
  guest_additions_mode = "disable"
}

// ---------- build ----------

build {
  name = "nthedao-ubuntu2404-arm64-hardened"
  // Both sources share the same provisioners (python bootstrap + ansible
  // compliance role). Filter at invocation time with `-only` to bake just one
  // provider; the build.sh wrapper does this based on the PROVIDER env var.
  sources = [
    "source.qemu.nthedao-ubuntu2404-arm64",
    "source.virtualbox-ovf.nthedao-ubuntu2404-arm64",
  ]

  // Bootstrap python — defensive. The base SHOULD already have python3 /
  // python3-apt from cloud-init, but re-asserting makes stage 2 robust against
  // bases built without that user-data. Idempotent.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo '${var.ssh_username}' | sudo -S apt-get update",
      "echo '${var.ssh_username}' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-apt aptitude",
    ]
  }

  // Compliance role — direct ansible. Same provisioner config as bosch/22.04,
  // only the source it runs against differs.
  provisioner "ansible" {
    playbook_file           = "playbooks/packer-bake.yml"
    inventory_file_template = "default ansible_host={{ .Host }} ansible_user={{ .User }} ansible_port={{ .Port }}\n"
    user                    = var.ssh_username
    use_proxy               = false
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "-v",
    ]
    ansible_env_vars = [
      "ANSIBLE_CONFIG=playbooks/ansible.cfg",
      "COMPLIANCE_PROFILE=${var.compliance_profile}",
      "FIPS_MODE=${var.fips_mode}",
      "TENANT=${var.tenant}",
      "IMAGE_VERSION=${var.image_version}",
      "ANSIBLE_HOST_KEY_CHECKING=False",
    ]
  }

  // ----- Vagrant box (virtualbox source) -----
  // Wraps the .ova into a provider-locked .box. `only` restricts to the
  // virtualbox-ovf source. keep_input_artifact preserves the .ova alongside.
  //   vagrant box add nthedao-arm64 ./nthedao-ubuntu2404-cisl1-arm64-<ver>.box
  //   vagrant init nthedao-arm64 && vagrant up --provider virtualbox
  post-processor "vagrant" {
    only                = ["virtualbox-ovf.nthedao-ubuntu2404-arm64"]
    output              = "${local.output_dir_virtualbox}/${var.image_name_prefix}-${var.image_version}.box"
    keep_input_artifact = true
    compression_level   = 6
  }

  // ----- Vagrant box (qemu source) -----
  // Packer's stock `vagrant` PP doesn't emit qemu-provider boxes. We
  // hand-assemble the .box (tar.gz of metadata.json + Vagrantfile + box.img +
  // efivars.fd) with shell-local. metadata.json's "provider" MUST be "libvirt"
  // (vagrant-qemu reuses vagrant-libvirt's box format), NOT "qemu".
  //
  // Engineer-side usage on Apple Silicon:
  //   vagrant plugin install vagrant-qemu
  //   vagrant box add nthedao2705/ubuntu2404-cisl1-arm64 ./<box>.box \
  //     --provider libvirt --architecture arm64
  //   vagrant init nthedao2705/ubuntu2404-cisl1-arm64 && vagrant up --provider qemu
  post-processor "shell-local" {
    only           = ["qemu.nthedao-ubuntu2404-arm64"]
    inline_shebang = "/bin/bash -euo pipefail"
    environment_vars = [
      "OUTPUT_DIR=${local.output_dir_qemu}",
      "BOX_NAME=${var.image_name_prefix}-${var.image_version}.box",
      "QCOW2_NAME=${var.image_name_prefix}-${var.image_version}.qcow2",
      // path.root is this file's dir (templates/nthedao/). box-vagrantfile.qemu.rb
      // is shared and lives one level up in templates/, so reference it via ../.
      // abspath(): the shell-local script `cd`s into $OUTPUT_DIR before using
      // this, so a relative path (path.root is relative when packer is invoked
      // with a relative template path) would break the later `cp`. Absolute
      // survives the cd.
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

  // ----- Manifest (one per source) -----
  post-processor "manifest" {
    only       = ["qemu.nthedao-ubuntu2404-arm64"]
    output     = "${local.output_dir_qemu}/manifest.json"
    strip_path = true
    custom_data = {
      stage              = "hardened"
      tenant             = var.tenant
      provider           = "qemu"
      compliance_profile = var.compliance_profile
      fips_mode          = var.fips_mode
      image_version      = var.image_version
      arch               = "arm64"
      base_image_path    = var.base_image_path
    }
  }

  post-processor "manifest" {
    only       = ["virtualbox-ovf.nthedao-ubuntu2404-arm64"]
    output     = "${local.output_dir_virtualbox}/manifest.json"
    strip_path = true
    custom_data = {
      stage               = "hardened"
      tenant              = var.tenant
      provider            = "virtualbox"
      compliance_profile  = var.compliance_profile
      fips_mode           = var.fips_mode
      image_version       = var.image_version
      arch                = "arm64"
      base_image_ova_path = var.base_image_ova_path
    }
  }
}
