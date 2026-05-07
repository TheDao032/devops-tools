// Bosch — Ubuntu 22.04 ARM64 hardened image (CIS-L1, no FIPS).
//
// STAGE 2 of the two-stage build. This template does NOT install the OS —
// it boots the qcow2 produced by stage 1 (templates/ubuntu2204-arm64-base.pkr.hcl)
// and runs the compliance role against it. Iteration cost: ~3 min per ansible
// edit, vs ~12-15 min for a full install+ansible cycle.
//
// Build:
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh bosch qemu        # qcow2 only
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh bosch virtualbox  # ova + box
//   STAGE=hardened ARCH=arm64 ./scripts/build.sh bosch all         # both, parallel
// or directly:
//   packer init templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl
//   packer build \
//     -var-file=variables/common.pkrvars.hcl \
//     -var-file=variables/bosch-arm64.pkrvars.hcl \
//     -var ssh_private_key_file=keys/packer_ed25519 \
//     -var base_image_path=output/base/ubuntu2204-arm64/<base-ver>/ubuntu2204-arm64-base-<base-ver>.qcow2 \
//     -var base_image_ova_path=output/base/ubuntu2204-arm64-vbox/<base-ver>/ubuntu2204-arm64-base-<base-ver>.ova \
//     -only=qemu.bosch-ubuntu2204-arm64 \    # or virtualbox-ovf.bosch-ubuntu2204-arm64
//     templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl
//
// Output:
//   qemu:       output/bosch/arm64/qemu/<image_version>/<image_name_prefix>-<image_version>.qcow2
//   virtualbox: output/bosch/arm64/virtualbox/<image_version>/<image_name_prefix>-<image_version>.{ova,box}
//
// SSH key contract:
//   Stage 1 baked the public half of keys/packer_ed25519 into the base image's
//   ~packer/.ssh/authorized_keys via cloud-init. This stage's qemu source uses
//   the matching private key for both packer's own SSH and the ansible
//   provisioner. If you regenerate the keypair, re-bake the base — the old
//   base image's authorized_keys won't accept the new key.
//
// Provider scope (Path D):
//   Two sources, each producing TWO deliverables (qcow2/ova for prod-style
//   consumers + .box for vagrant consumers):
//     - qemu             → qcow2  + .box (provider=qemu, vagrant-qemu plugin)
//     - virtualbox-ovf   → ova    + .box (provider=virtualbox)
//   Both .box files target Apple Silicon engineer dev sandboxes; consumers
//   pick the provider that matches their hypervisor. virtualbox = stock
//   `vagrant` post-processor (HashiCorp). qemu = `shell-local` post-processor
//   that hand-assembles the box archive, because Packer's stock `vagrant`
//   PP does NOT emit qemu-provider boxes (its supported providers are
//   virtualbox/vmware/hyperv/libvirt/parallels/docker only).
//
//   Both sources consume stage 1's pre-baked image:
//     - qemu source       → .qcow2 from stage 1's qemu source (var.base_image_path)
//     - virtualbox-ovf    → .ova   from stage 1's vbox source (var.base_image_ova_path)
//   The same ansible compliance role runs against both — the harden-once
//   contract is preserved (one role, multiple provider artifacts).
//
//   Other providers (vmware-vmx, parallels-pvm) are still out of scope —
//   each needs its own consume-pre-baked-disk source. See README.md
//   "Vagrant box consumption" for the per-arch provider matrix and
//   chef/bento for canonical recipes.

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    qemu       = { source = "github.com/hashicorp/qemu", version = "~> 1.1" }
    ansible    = { source = "github.com/hashicorp/ansible", version = "~> 1.1" }
    // Path D additions — virtualbox source + vagrant post-processor for
    // the .box deliverable. See provider-scope comment above.
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

// EFI firmware — same defaults as stage 1. Stage 2 boots with EFI because
// the base image was installed under EFI; switching firmware between stages
// would brick the boot loader.
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

// Path to the stage 1 qcow2 base image. Required only when building the qemu
// source (i.e. PROVIDER=qemu or PROVIDER=all). Defaulted to empty so vbox-only
// builds don't have to supply it; build.sh resolves the actual path via the
// latest/ symlink convention. Override via -var base_image_path=... to point
// at any qcow2 (e.g. an older half-baked image to iterate ansible against
// without re-baking).
variable "base_image_path" {
  type        = string
  default     = ""
  description = "Path to the qcow2 produced by stage 1's qemu source. Empty is fine for virtualbox-only builds (filtered via -only)."
}

// Path to the stage 1 VirtualBox base .ova. Required only when building the
// virtualbox-ovf source (i.e. PROVIDER=virtualbox or PROVIDER=all). Defaulted
// to empty so qemu-only builds don't have to supply it; build.sh resolves
// the actual path via the same latest/ symlink convention as base_image_path.
variable "base_image_ova_path" {
  type        = string
  default     = ""
  description = "Path to the .ova produced by stage 1's virtualbox-iso source. Empty is fine for qemu-only builds (filtered via -only)."
}

// ---------- locals ----------

locals {
  // Per-provider output dirs. Provider already lives in the path layout at
  // stage 2 (was always `<tenant>/<arch>/<provider>/<ver>/`), so this is just
  // adding a sibling for virtualbox alongside the existing qemu path.
  output_dir_qemu       = "${var.output_base_dir}/${var.tenant}/arm64/qemu/${var.image_version}"
  output_dir_virtualbox = "${var.output_base_dir}/${var.tenant}/arm64/virtualbox/${var.image_version}"
}

// ---------- source ----------

source "qemu" "bosch-ubuntu2204-arm64" {
  // disk_image = true tells packer "iso_url is a bootable disk, not an
  // installer ISO." No autoinstall, no http_directory, no boot_command —
  // packer just boots the qcow2 and waits for SSH.
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

  // Same aarch64+hvf qemuargs adjustments as stage 1. The base image was
  // installed under these conditions; deviating risks boot-time surprises.
  // See bosch-…-hardened.pkr.hcl history (or stage 1 template) for why each
  // line is here.
  qemuargs = [
    ["-boot", "strict=off"],
    ["-machine", "type=virt,accel=hvf,highmem=on"],
    ["-device", "virtio-net,netdev=user.0"],
    ["-device", "qemu-xhci"],
    ["-device", "usb-kbd"],
    ["-device", "usb-tablet"],
    ["-device", "ramfb"],
    ["-device", "virtio-gpu-pci"],
  ]
}

// virtualbox-ovf consumes stage 1's pre-baked .ova (NOT the ISO — no
// reinstall happens). Packer imports the OVA into a fresh VBox VM, runs
// the same provisioners as the qemu source, then re-exports as .ova for
// the vagrant post-processor to wrap into a .box.
source "virtualbox-ovf" "bosch-ubuntu2204-arm64" {
  // source_path can be either a .ova or .ovf. We use .ova because stage 1
  // exports a single self-contained .ova file (simpler than wrangling an
  // .ovf + sidecar .vmdk).
  source_path = var.base_image_ova_path
  // checksum = "none" because source_path is a local artifact under our own
  // control (build pipeline output), not a remote download where checksum
  // would guard against corrupted transfer.
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

  // Guest Additions has no working arm64 build — see stage 1 source for
  // the same disable. Avoids a wasted download/install cycle.
  guest_additions_mode = "disable"
}

// ---------- build ----------

build {
  name = "bosch-ubuntu2204-arm64-hardened"
  // Both sources share the same provisioners (python bootstrap + ansible
  // compliance role). Filter at invocation time with `-only` to bake just
  // one provider when iterating; the build.sh wrapper does this based on
  // the PROVIDER env var.
  sources = [
    "source.qemu.bosch-ubuntu2204-arm64",
    "source.virtualbox-ovf.bosch-ubuntu2204-arm64",
  ]

  // Bootstrap python — defensive. The base SHOULD already have python3 and
  // python3-apt from cloud-init's packages list, but re-asserting here makes
  // stage 2 robust against bases built without that user-data, or against a
  // user-supplied base from outside the pipeline. Idempotent.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo '${var.ssh_username}' | sudo -S apt-get update",
      "echo '${var.ssh_username}' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-apt aptitude",
    ]
  }

  // Compliance role — direct ansible. Same provisioner config as the legacy
  // monolith, only difference is the source it's running against.
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
  // The `vagrant` post-processor wraps the .ova into a provider-locked .box
  // that Vagrant can consume directly. `only` restricts this to the
  // virtualbox-ovf source.
  //
  // keep_input_artifact = true preserves the .ova alongside the .box so
  // power users can `VBoxManage import` directly without going through
  // vagrant. compression_level = 6 is the standard zlib trade-off (good
  // ratio without burning CPU).
  //
  // Engineer-side usage on Apple Silicon:
  //   vagrant box add bosch-arm64 ./bosch-ubuntu2204-cisl1-arm64-<ver>.box
  //   vagrant init bosch-arm64 && vagrant up --provider virtualbox
  post-processor "vagrant" {
    only                = ["virtualbox-ovf.bosch-ubuntu2204-arm64"]
    output              = "${local.output_dir_virtualbox}/${var.image_name_prefix}-${var.image_version}.box"
    keep_input_artifact = true
    compression_level   = 6
  }

  // ----- Vagrant box (qemu source) -----
  // Packer's stock `vagrant` PP doesn't emit `provider=qemu` boxes. We
  // hand-assemble the .box (tar.gz of metadata.json + Vagrantfile + box.img)
  // with shell-local. The Vagrantfile shipped INSIDE the .box is the static
  // template at templates/box-vagrantfile.qemu.rb — edit that file (not
  // this PP) to change the per-box defaults engineers receive.
  //
  // Engineer-side usage on Apple Silicon:
  //   vagrant plugin install vagrant-qemu
  //   vagrant box add bosch-arm64 ./bosch-ubuntu2204-cisl1-arm64-<ver>.box
  //   vagrant init bosch-arm64 && vagrant up --provider qemu
  //
  // architecture=arm64 is stamped into metadata.json so Vagrant Cloud's
  // multi-arch resolver picks this box only for arm64 consumers.
  post-processor "shell-local" {
    only           = ["qemu.bosch-ubuntu2204-arm64"]
    inline_shebang = "/bin/bash -euo pipefail"
    environment_vars = [
      "OUTPUT_DIR=${local.output_dir_qemu}",
      "BOX_NAME=${var.image_name_prefix}-${var.image_version}.box",
      "QCOW2_NAME=${var.image_name_prefix}-${var.image_version}.qcow2",
      "VAGRANTFILE_TEMPLATE=${path.root}/templates/box-vagrantfile.qemu.rb",
    ]
    inline = [
      "set -x",
      "test -f \"$VAGRANTFILE_TEMPLATE\" || { echo \"missing $VAGRANTFILE_TEMPLATE\" >&2; exit 1; }",
      "cd \"$OUTPUT_DIR\"",
      "test -f \"$QCOW2_NAME\" || { echo \"missing qcow2 in $OUTPUT_DIR: $QCOW2_NAME\" >&2; exit 1; }",
      "stage=$(mktemp -d -t vagrant-qemu-box-XXXXXX)",
      "trap 'rm -rf \"$stage\"' EXIT",
      "cp \"$QCOW2_NAME\" \"$stage/box.img\"",
      "printf '%s\\n' '{\"provider\":\"qemu\",\"format\":\"qcow2\",\"architecture\":\"arm64\"}' > \"$stage/metadata.json\"",
      "cp \"$VAGRANTFILE_TEMPLATE\" \"$stage/Vagrantfile\"",
      "tar -czf \"$BOX_NAME\" -C \"$stage\" metadata.json Vagrantfile box.img",
      "ls -lh \"$BOX_NAME\"",
    ]
  }

  // ----- Manifest (one per source, parked alongside that source's artifact) -----
  // `only` filtering is required: without it, both manifest blocks would
  // fire for both sources and overwrite each other's outputs.
  post-processor "manifest" {
    only       = ["qemu.bosch-ubuntu2204-arm64"]
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
    only       = ["virtualbox-ovf.bosch-ubuntu2204-arm64"]
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
