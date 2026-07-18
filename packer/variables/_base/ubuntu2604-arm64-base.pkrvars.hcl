# Ubuntu 26.04 ARM64 — variables for the STAGE 1 base bake.
# Pairs with: templates/_base/ubuntu2604-arm64-base.pkr.hcl
#
# Produces a tenant-AGNOSTIC 26.04 base image. Tenant-specific values
# (compliance profile, banner, per-tenant image_name_prefix) live in
# variables/<org>/arm64.pkrvars.hcl and are consumed by stage 2.
#
# Refresh cadence: re-bake when Ubuntu cuts a 26.04 point release with security
# fixes you care about, OR quarterly, OR on demand. The base does NOT need a
# re-bake when the compliance role changes — that's stage 2.

# Ubuntu 26.04 LTS server ARM64 ("Resolute Raccoon").
# Cache the ISO locally first (matches the 22.04 base convention):
#   curl -Lo ~/iso-cache/ubuntu-26.04-live-server-arm64.iso <release-url>
iso_url      = "file:///Users/thedao/iso-cache/ubuntu-26.04-live-server-arm64.iso"
iso_checksum = "sha256:c9aa567e6560b2eddae3af03fc686002e35b6fee96f97fd5df3271e846439fdd"

# Bootstrap user — created by cloud-init autoinstall. Stage 2's ansible
# provisioner SSHes in as this user. Compliance role tightens or removes it.
ssh_username = "packer"

# Output filename. Version goes in the directory; the qcow2 itself has a stable
# name so `latest` symlinks (output/base/ubuntu2604-arm64/latest/...) are easy.
image_name_prefix = "ubuntu2604-arm64-base"
