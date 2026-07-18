# Guest: Ubuntu 22.04.5 LTS (Jammy Jellyfish) — amd64
# Paired with: templates/_base/ubuntu-amd64.pkr.hcl
#
# iso_url is composed at template-eval time as:
#   "${var.iso_cache_prefix}/${var.iso_filename}"
# Where iso_cache_prefix comes from variables/local.pkrvars.hcl (per-machine).

iso_filename = "ubuntu-22.04.5-live-server-amd64.iso"
iso_checksum = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
guest_slug   = "ubuntu2204"

# Default ssh user Packer uses during autoinstall (matches http/user-data identity block).
ssh_username = "packer"
