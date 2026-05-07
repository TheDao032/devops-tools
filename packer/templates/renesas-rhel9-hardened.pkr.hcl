// Renesas — RHEL 9 hardened image (CIS-L2 + FIPS 140-3).
//
// Build:
//   packer init templates/renesas-rhel9-hardened.pkr.hcl
//   packer build \
//     -var-file=variables/common.pkrvars.hcl \
//     -var-file=variables/renesas.pkrvars.hcl \
//     -only="<source-name>" \
//     templates/renesas-rhel9-hardened.pkr.hcl
//
// Sources:
//   virtualbox-iso.renesas-rhel9   — for Vagrant dev sandboxes (.box)
//   qemu.renesas-rhel9             — for Proxmox prod (qcow2)
//   vmware-iso.renesas-rhel9       — for VMware Fusion engineer laptops

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
variable "rhel_subscription_pool_id" {
  type    = string
  default = ""
}

// ---------- locals ----------

locals {
  // Output dir root. Each source block appends its own provider segment; we
  // do NOT use Packer's `{{.Provider}}` substitution here because that token
  // is a legacy v1 (JSON) template variable that does not interpolate in HCL2
  // `locals` blocks — it would render literally as `<no value>`.
  output_root = "${var.output_base_dir}/${var.tenant}"

  // Per-source artifact directories. Pinned at evaluation time so they are
  // visible to post-processors (and free of Packer's runtime substitution).
  output_dir_virtualbox = "${local.output_root}/virtualbox-iso/${var.image_version}"
  output_dir_qemu       = "${local.output_root}/qemu/${var.image_version}"
  output_dir_vmware     = "${local.output_root}/vmware-iso/${var.image_version}"

  // Boot command for RHEL 9 anaconda kickstart over HTTP.
  boot_command_rhel = [
    "<wait>",
    "<tab> inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks-rhel.cfg<enter>",
  ]
}

// ---------- sources ----------

source "virtualbox-iso" "renesas-rhel9" {
  iso_url              = var.iso_url
  iso_checksum         = var.iso_checksum
  guest_os_type        = "RedHat_64"
  cpus                 = var.build_cpus
  memory               = var.build_memory
  disk_size            = var.disk_size_mb
  http_directory       = "http"
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_username // kickstart sets matching password; rotated post-bake
  ssh_timeout          = var.ssh_timeout
  shutdown_command     = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait            = "5s"
  boot_command         = local.boot_command_rhel
  format               = "ova"
  output_directory     = local.output_dir_virtualbox
  vm_name              = "${var.image_name_prefix}-${var.image_version}"
  guest_additions_mode = "disable"
}

source "qemu" "renesas-rhel9" {
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  cpus             = var.build_cpus
  memory           = var.build_memory
  disk_size        = "${var.disk_size_mb}M"
  format           = "qcow2"
  accelerator      = "kvm" // override to "hvf" on macOS via -var
  http_directory   = "http"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_username
  ssh_timeout      = var.ssh_timeout
  shutdown_command = "echo '${var.ssh_username}' | sudo -S /sbin/shutdown -hP now"
  boot_wait        = "5s"
  boot_command     = local.boot_command_rhel
  output_directory = local.output_dir_qemu
  vm_name          = "${var.image_name_prefix}-${var.image_version}.qcow2"
  headless         = true
  net_device       = "virtio-net"
  disk_interface   = "virtio"
}

source "vmware-iso" "renesas-rhel9" {
  iso_url          = var.iso_url
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
  vm_name          = "${var.image_name_prefix}-${var.image_version}"
  headless         = true
}

// ---------- build ----------

build {
  name = "renesas-rhel9-hardened"

  sources = [
    "source.virtualbox-iso.renesas-rhel9",
    "source.qemu.renesas-rhel9",
    "source.vmware-iso.renesas-rhel9",
  ]

  // Subscribe RHEL via subscription-manager BEFORE the compliance role runs;
  // FIPS enablement and many CIS-L2 packages need access to the BaseOS repo.
  // Credentials come from env so they never land in HCL.
  provisioner "shell" {
    inline = [
      "set -e",
      "if [ -n \"$RHEL_USERNAME\" ] && [ -n \"$RHEL_PASSWORD\" ]; then",
      "  echo '$RHEL_PASSWORD' | sudo -S subscription-manager register --username=$RHEL_USERNAME --password=$RHEL_PASSWORD --auto-attach || true",
      "fi",
      "echo '${var.ssh_username}' | sudo -S dnf -y install python3 python3-libselinux",
    ]
    environment_vars = [
      "RHEL_USERNAME=${env("RHEL_USERNAME")}",
      "RHEL_PASSWORD=${env("RHEL_PASSWORD")}",
    ]
  }

  // The compliance role does the actual hardening. Profile + FIPS toggle
  // are passed via env, read by playbooks/packer-bake.yml. Single source of
  // truth for hardening — same role used by deploy.sh on real hardware.
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

  // Optional: detach RHEL subscription before image is sealed so the baked
  // image isn't tied to one subscription. Real nodes re-attach via the
  // ansible runtime role.
  provisioner "shell" {
    inline = [
      "if command -v subscription-manager >/dev/null 2>&1; then",
      "  echo '${var.ssh_username}' | sudo -S subscription-manager unregister || true",
      "fi",
    ]
  }

  // Post-processor: convert virtualbox output to a Vagrant box for the dev
  // sandbox flow. Only runs against the virtualbox source.
  post-processor "vagrant" {
    only                = ["virtualbox-iso.renesas-rhel9"]
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
