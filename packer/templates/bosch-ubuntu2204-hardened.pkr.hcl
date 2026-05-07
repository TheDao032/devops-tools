// Bosch — Ubuntu 22.04 LTS hardened image (CIS-L1, no FIPS).
//
// Build:
//   packer init templates/bosch-ubuntu2204-hardened.pkr.hcl
//   packer build \
//     -var-file=variables/common.pkrvars.hcl \
//     -var-file=variables/bosch.pkrvars.hcl \
//     -only="<source-name>" \
//     templates/bosch-ubuntu2204-hardened.pkr.hcl

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    virtualbox = { source = "github.com/hashicorp/virtualbox", version = "~> 1.0" }
    qemu       = { source = "github.com/hashicorp/qemu", version = "~> 1.1" }
    vmware     = { source = "github.com/hashicorp/vmware", version = "~> 1.0" }
    ansible    = { source = "github.com/hashicorp/ansible", version = "~> 1.1" }
    vagrant    = { source = "github.com/hashicorp/vagrant", version = "~> 1.1" }
  }
}

// ---------- variables ----------

variable "tenant" { type = string }
variable "compliance_profile" { type = string }
variable "fips_mode" { type = string }
variable "iso_url" { type = string }
variable "iso_checksum" { type = string }
variable "ssh_username" { type = string }
variable "ssh_timeout" { type = string }
variable "login_banner" { type = string }
variable "image_version" { type = string }
variable "image_name_prefix" { type = string }
variable "output_base_dir" { type = string }
variable "build_cpus" { type = number }
variable "build_memory" { type = number }
variable "disk_size_mb" { type = number }

// ---------- locals ----------

locals {
  // Output dir root. Each source block appends its own provider segment; we
  // do NOT use Packer's `{{.Provider}}` substitution here because that token
  // is a legacy v1 (JSON) template variable that does not interpolate in HCL2
  // `locals` blocks — it would render literally as `<no value>` (which is
  // exactly the bug that produced `output/bosch/<no value>/...` directories
  // before this fix).
  output_root = "${var.output_base_dir}/${var.tenant}"

  // Per-source artifact directories. Pinned at evaluation time so they are
  // visible to post-processors (and free of Packer's runtime substitution).
  output_dir_virtualbox = "${local.output_root}/virtualbox-iso/${var.image_version}"
  output_dir_qemu       = "${local.output_root}/qemu/${var.image_version}"
  output_dir_vmware     = "${local.output_root}/vmware-iso/${var.image_version}"

  // Ubuntu 22.04 autoinstall (subiquity) boot command.
  // 'autoinstall' tells subiquity to run unattended via cloud-init datasource.
  boot_command_ubuntu = [
    "<wait>",
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ",
    "<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>",
  ]
}

// ---------- sources ----------

source "virtualbox-iso" "bosch-ubuntu2204" {
  iso_url              = var.iso_url
  iso_checksum         = var.iso_checksum
  guest_os_type        = "Ubuntu_64"
  cpus                 = var.build_cpus
  memory               = var.build_memory
  disk_size            = var.disk_size_mb
  http_directory       = "http"
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_username
  ssh_timeout          = var.ssh_timeout
  shutdown_command     = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait            = "5s"
  boot_command         = local.boot_command_ubuntu
  format               = "ova"
  output_directory     = local.output_dir_virtualbox
  vm_name              = "${var.image_name_prefix}-${var.image_version}"
  guest_additions_mode = "disable"
}

source "qemu" "bosch-ubuntu2204" {
  iso_url          = var.iso_url
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
  boot_wait        = "5s"
  boot_command     = local.boot_command_ubuntu
  output_directory = local.output_dir_qemu
  vm_name          = "${var.image_name_prefix}-${var.image_version}.qcow2"
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"
}

source "vmware-iso" "bosch-ubuntu2204" {
  iso_url          = var.iso_url
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
  boot_wait        = "5s"
  boot_command     = local.boot_command_ubuntu
  output_directory = local.output_dir_vmware
  vm_name          = "${var.image_name_prefix}-${var.image_version}"
  headless         = true
}

// ---------- build ----------

build {
  name = "bosch-ubuntu2204-hardened"

  sources = [
    "source.virtualbox-iso.bosch-ubuntu2204",
    "source.qemu.bosch-ubuntu2204",
    "source.vmware-iso.bosch-ubuntu2204",
  ]

  // Bootstrap python so the ansible provisioner has an interpreter, plus
  // common deps the compliance role expects.
  provisioner "shell" {
    inline = [
      "set -e",
      "echo '${var.ssh_username}' | sudo -S apt-get update",
      "echo '${var.ssh_username}' | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-apt aptitude",
    ]
  }

  // Compliance role runs CIS-L1 (no FIPS for Bosch). Same role definition
  // as Renesas — only the env-var inputs differ.
  provisioner "ansible" {
    playbook_file           = "playbooks/packer-bake.yml"
    inventory_file_template = "default ansible_host=default ansible_user=${var.ssh_username}\n"
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

  // Vagrant box conversion for dev sandboxes. virtualbox-only — output goes
  // alongside the .ova in the virtualbox-iso artifact directory.
  post-processor "vagrant" {
    only                = ["virtualbox-iso.bosch-ubuntu2204"]
    output              = "${local.output_dir_virtualbox}/${var.image_name_prefix}-${var.image_version}.box"
    keep_input_artifact = false
  }

  // Single tenant-level manifest. The manifest post-processor accumulates
  // entries across sources, so every (provider) artifact is provable from one
  // file rather than three separate per-provider manifests.
  post-processor "manifest" {
    output     = "${local.output_root}/manifest.json"
    strip_path = true
    custom_data = {
      tenant             = var.tenant
      compliance_profile = var.compliance_profile
      fips_mode          = var.fips_mode
      image_version      = var.image_version
      arch               = "amd64"
    }
  }
}
