// Ubuntu (any 2x.04 LTS) — amd64 hardened image.
//
// This template is TENANT-AGNOSTIC and GUEST-VERSION-AGNOSTIC. All the
// version- and tenant-specific bits come from separate pkrvars files:
//
//   -var-file=variables/common.pkrvars.hcl           # sizing, timeouts
//   -var-file=variables/local.pkrvars.hcl            # iso_cache_prefix (per-machine, gitignored)
//   -var-file=variables/guest/ubuntu<VER>-amd64.pkrvars.hcl  # iso_filename, iso_checksum, guest_slug
//   -var-file=variables/tenants/<tenant>.pkrvars.hcl # compliance_profile, banner, image_name_prefix, etc.
//
// scripts/build.sh composes these for you.
//
// Compat notes:
//   - Ubuntu 22.04 + 24.04 both use subiquity autoinstall v1 → same boot cmd.
//   - guest_os_type = "Ubuntu_64" is generic across VirtualBox 7.x.
//   - If a future Ubuntu release breaks autoinstall v1, fork this template.

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    virtualbox = { source = "github.com/hashicorp/virtualbox", version = "~> 1.0" }
    qemu       = { source = "github.com/hashicorp/qemu",       version = "~> 1.1" }
    vmware     = { source = "github.com/hashicorp/vmware",     version = "~> 1.0" }
    ansible    = { source = "github.com/hashicorp/ansible",    version = "~> 1.1" }
    vagrant    = { source = "github.com/hashicorp/vagrant",    version = "~> 1.1" }
  }
}

// ---------- variables ----------

// Tenant layer (from variables/tenants/<tenant>.pkrvars.hcl)
variable "tenant"             { type = string }
variable "compliance_profile" { type = string }
variable "fips_mode"          { type = string }
variable "login_banner"       { type = string }
variable "image_name_prefix"  { type = string }  // e.g. "bosch-cisl1"

// Guest layer (from variables/guest/ubuntu<VER>-amd64.pkrvars.hcl)
variable "iso_filename" { type = string }  // e.g. "ubuntu-24.04.4-live-server-amd64.iso"
variable "iso_checksum" { type = string }
variable "guest_slug"   { type = string }  // e.g. "ubuntu2404"

// Machine-local layer (from variables/local.pkrvars.hcl — gitignored)
variable "iso_cache_prefix" {
  type    = string
  default = ""    // Must be provided at build time; empty causes iso_url to be a bare filename → packer will fail loudly.
}

// Common layer (from variables/common.pkrvars.hcl)
variable "output_base_dir" { type = string }
variable "image_version"   { type = string }
variable "ssh_username"    { type = string }
variable "ssh_timeout"     { type = string }
variable "build_cpus"      { type = number }
variable "build_memory"    { type = number }
variable "disk_size_mb"    { type = number }

// Used by all sources for key-based SSH auth. build.sh passes the path to
// keys/packer_ed25519, whose matching pubkey is baked into the target VM's
// authorized_keys via http/user-data.tmpl's @@SSH_PUBKEY@@ substitution.
//
// Why key auth (not password): packer-plugin-ansible v1.1.5 generates its own
// temp SSH key at provisioner time that modern OpenSSH refuses to load
// ("error in libcrypto" — hit on 2026-07-08). Handing our own valid key via
// ssh_private_key_file makes the plugin skip its broken temp-key path.
variable "ssh_private_key_file" {
  type    = string
  default = ""
}

// ---------- locals ----------

locals {
  // Compose the actual ISO URL from machine-local prefix + guest filename.
  iso_url = "${var.iso_cache_prefix}/${var.iso_filename}"

  // Per-guest output dir root: output/<tenant>/<guest_slug>/<provider>/<version>/
  output_root           = "${var.output_base_dir}/${var.tenant}/${var.guest_slug}"
  output_dir_virtualbox = "${local.output_root}/virtualbox-iso/${var.image_version}"
  output_dir_qemu       = "${local.output_root}/qemu/${var.image_version}"
  output_dir_vmware     = "${local.output_root}/vmware-iso/${var.image_version}"

  // Full VM/image name: e.g. "bosch-cisl1-ubuntu2404-2026-07-07.1"
  image_name = "${var.image_name_prefix}-${var.guest_slug}-${var.image_version}"

  // Ubuntu 22.04 + 24.04 autoinstall (subiquity) boot command.
  //
  // Two gotchas encoded here (both bit us on the 2026-07-08 first bake):
  //   1. `boot_wait` (on the source) must be >=10s on 24.04. GRUB's keyboard
  //      handler on VBox isn't ready at 5s and eats the first `c`.
  //   2. The ds= argument MUST be double-quoted. GRUB command-line treats `;`
  //      as a command separator, so an unquoted `ds=nocloud-net;s=http://...`
  //      becomes two commands — the kernel boots without the seed URL and
  //      subiquity drops to interactive mode with no console visible.
  boot_command_ubuntu = [
    "<wait>",
    "c<wait2s>",
    "linux /casper/vmlinuz --- autoinstall \"ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/\"",
    "<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>",
  ]
}

// ---------- sources ----------

source "virtualbox-iso" "ubuntu" {
  iso_url              = local.iso_url
  iso_checksum         = var.iso_checksum
  guest_os_type        = "Ubuntu_64"
  cpus                 = var.build_cpus
  memory               = var.build_memory
  disk_size            = var.disk_size_mb
  http_directory       = "http"
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_username           // debug fallback; also required by ssh_wait during autoinstall
  ssh_private_key_file = var.ssh_private_key_file   // primary auth; also inherited by ansible provisioner
  ssh_timeout          = var.ssh_timeout
  shutdown_command     = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait            = "10s"
  boot_command         = local.boot_command_ubuntu
  format               = "ova"
  output_directory     = local.output_dir_virtualbox
  vm_name              = local.image_name
  guest_additions_mode = "disable"
}

source "qemu" "ubuntu" {
  iso_url          = local.iso_url
  iso_checksum     = var.iso_checksum
  cpus             = var.build_cpus
  memory           = var.build_memory
  disk_size        = "${var.disk_size_mb}M"
  format           = "qcow2"
  accelerator      = "kvm"
  http_directory   = "http"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_username
  ssh_timeout      = var.ssh_timeout
  shutdown_command = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait        = "10s"
  boot_command     = local.boot_command_ubuntu
  output_directory = local.output_dir_qemu
  vm_name          = "${local.image_name}.qcow2"
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"
}

source "vmware-iso" "ubuntu" {
  iso_url          = local.iso_url
  iso_checksum     = var.iso_checksum
  guest_os_type    = "ubuntu-64"
  cpus             = var.build_cpus
  memory           = var.build_memory
  disk_size        = var.disk_size_mb
  http_directory   = "http"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_username
  ssh_timeout      = var.ssh_timeout
  shutdown_command = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait        = "10s"
  boot_command     = local.boot_command_ubuntu
  output_directory = local.output_dir_vmware
  vm_name          = local.image_name
  headless         = true
}

// ---------- build ----------

build {
  name = "ubuntu-amd64"

  sources = [
    "source.virtualbox-iso.ubuntu",
    "source.qemu.ubuntu",
    "source.vmware-iso.ubuntu",
  ]

  // Bootstrap python so the ansible provisioner has an interpreter.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo '${var.ssh_username}' | sudo -S apt-get update",
      "echo '${var.ssh_username}' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-apt aptitude",
    ]
  }

  // Compliance role — CIS-Lx per tenant, FIPS toggle from tenant vars.
  //
  // We DO NOT set inventory_file_template — the plugin's default already emits
  //   "default ansible_host={{.Host}} ansible_user={{.User}} ansible_port={{.Port}}"
  // which points at the actual SSH port-forward Packer just set up (127.0.0.1:<port>).
  // A prior override wrote "ansible_host=default" as a literal string; ansible
  // tried to resolve DNS for "default" and everything died. See 2026-07-08 log.
  provisioner "ansible" {
    playbook_file = "playbooks/packer-bake.yml"
    galaxy_file   = "playbooks/requirements.yml"  // ansible.posix >= 2.0, community.general >= 12.0
    user          = var.ssh_username
    use_proxy     = false
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

  // Vagrant box conversion — virtualbox-iso source only.
  post-processor "vagrant" {
    only                = ["virtualbox-iso.ubuntu"]
    output              = "${local.output_dir_virtualbox}/${local.image_name}.box"
    keep_input_artifact = false
  }

  // Single tenant-level manifest (accumulates entries across sources).
  post-processor "manifest" {
    output     = "${local.output_root}/manifest.json"
    strip_path = true
    custom_data = {
      tenant             = var.tenant
      compliance_profile = var.compliance_profile
      fips_mode          = var.fips_mode
      image_version      = var.image_version
      guest              = var.guest_slug
      arch               = "amd64"
    }
  }
}
