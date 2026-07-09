// RHEL 9 (and forward) — amd64 hardened image.
//
// TENANT-AGNOSTIC and GUEST-VERSION-AGNOSTIC. Composed pkrvars pattern:
//
//   -var-file=variables/common.pkrvars.hcl
//   -var-file=variables/local.pkrvars.hcl                     # iso_cache_prefix
//   -var-file=variables/guest/rhel<N>-amd64.pkrvars.hcl       # iso_filename, iso_checksum, guest_slug
//   -var-file=variables/tenants/<tenant>.pkrvars.hcl          # compliance_profile, banner, image_name_prefix
//
// scripts/build.sh composes these for you.

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

// Tenant layer
variable "tenant"             { type = string }
variable "compliance_profile" { type = string }
variable "fips_mode"          { type = string }
variable "login_banner"       { type = string }
variable "image_name_prefix"  { type = string }

// Guest layer
variable "iso_filename" { type = string }
variable "iso_checksum" { type = string }
variable "guest_slug"   { type = string }  // e.g. "rhel9"

// Local layer (per-machine, gitignored)
variable "iso_cache_prefix" {
  type    = string
  default = ""
}

// Common layer
variable "output_base_dir" { type = string }
variable "image_version"   { type = string }
variable "ssh_username"    { type = string }
variable "ssh_timeout"     { type = string }
variable "build_cpus"      { type = number }
variable "build_memory"    { type = number }
variable "disk_size_mb"    { type = number }

// RHEL subscription placeholder (credentials come from env; see provisioner below)
variable "rhel_subscription_pool_id" {
  type    = string
  default = ""
}

// RHEL creds pulled from env at packer-init time (packer 1.15+ requires env()
// in a variable default; can't be called inline inside environment_vars).
// The wrapper script errors if these aren't set for renesas builds.
variable "rhel_username" {
  type      = string
  default   = env("RHEL_USERNAME")
  sensitive = true
}
variable "rhel_password" {
  type      = string
  default   = env("RHEL_PASSWORD")
  sensitive = true
}

// Declared for build.sh's unconditional -var pass; unused by these sources.
variable "ssh_private_key_file" {
  type    = string
  default = ""
}

// ---------- locals ----------

locals {
  iso_url = "${var.iso_cache_prefix}/${var.iso_filename}"

  output_root           = "${var.output_base_dir}/${var.tenant}/${var.guest_slug}"
  output_dir_virtualbox = "${local.output_root}/virtualbox-iso/${var.image_version}"
  output_dir_qemu       = "${local.output_root}/qemu/${var.image_version}"
  output_dir_vmware     = "${local.output_root}/vmware-iso/${var.image_version}"

  image_name = "${var.image_name_prefix}-${var.guest_slug}-${var.image_version}"

  // Anaconda kickstart over HTTP.
  boot_command_rhel = [
    "<wait>",
    "<tab> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks-rhel.cfg<enter>",
  ]
}

// ---------- sources ----------

source "virtualbox-iso" "rhel" {
  iso_url              = local.iso_url
  iso_checksum         = var.iso_checksum
  guest_os_type        = "RedHat_64"
  cpus                 = var.build_cpus
  memory               = var.build_memory
  disk_size            = var.disk_size_mb
  http_directory       = "http"
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_username
  ssh_timeout          = var.ssh_timeout
  shutdown_command     = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait            = "5s"
  boot_command         = local.boot_command_rhel
  format               = "ova"
  output_directory     = local.output_dir_virtualbox
  vm_name              = local.image_name
  guest_additions_mode = "disable"
}

source "qemu" "rhel" {
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
  boot_wait        = "5s"
  boot_command     = local.boot_command_rhel
  output_directory = local.output_dir_qemu
  vm_name          = "${local.image_name}.qcow2"
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"
}

source "vmware-iso" "rhel" {
  iso_url          = local.iso_url
  iso_checksum     = var.iso_checksum
  guest_os_type    = "rhel9-64"
  cpus             = var.build_cpus
  memory           = var.build_memory
  disk_size        = var.disk_size_mb
  http_directory   = "http"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_username
  ssh_timeout      = var.ssh_timeout
  shutdown_command = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait        = "5s"
  boot_command     = local.boot_command_rhel
  output_directory = local.output_dir_vmware
  vm_name          = local.image_name
  headless         = true
}

// ---------- build ----------

build {
  name = "rhel-amd64"

  sources = [
    "source.virtualbox-iso.rhel",
    "source.qemu.rhel",
    "source.vmware-iso.rhel",
  ]

  provisioner "shell" {
    inline = [
      "set -e",
      "if [ -n \"$RHEL_USERNAME\" ] && [ -n \"$RHEL_PASSWORD\" ]; then",
      "  echo '$RHEL_PASSWORD' | sudo -S subscription-manager register --username=$RHEL_USERNAME --password=$RHEL_PASSWORD --auto-attach || true",
      "fi",
      "echo '${var.ssh_username}' | sudo -S dnf -y install python3 python3-libselinux",
    ]
    environment_vars = [
      "RHEL_USERNAME=${var.rhel_username}",
      "RHEL_PASSWORD=${var.rhel_password}",
    ]
  }

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

  provisioner "shell" {
    inline = [
      "if command -v subscription-manager >/dev/null 2>&1; then",
      "  echo '${var.ssh_username}' | sudo -S subscription-manager unregister || true",
      "fi",
    ]
  }

  post-processor "vagrant" {
    only                = ["virtualbox-iso.rhel"]
    output              = "${local.output_dir_virtualbox}/${local.image_name}.box"
    keep_input_artifact = false
  }

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
