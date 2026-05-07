# Ubuntu 22.04 ARM64 — variables for the STAGE 1 base bake.
# Pairs with: templates/ubuntu2204-arm64-base.pkr.hcl
#
# This produces a tenant-AGNOSTIC base image. Tenant-specific values
# (compliance profile, banner text, image_name_prefix per tenant) live in
# variables/<tenant>-arm64.pkrvars.hcl and are consumed by stage 2.
#
# Refresh cadence: re-bake when Ubuntu cuts a point release with security
# fixes you care about, OR quarterly, OR on demand. The base does NOT need
# to be re-baked when the compliance role changes — that's stage 2.

# Ubuntu 22.04.5 LTS server ARM64. Same source as bosch-arm64.pkrvars.hcl
# previously held — kept here so the base bake is self-contained.
iso_url      = "file:///Users/thedao/iso-cache/ubuntu-22.04.5-live-server-arm64.iso"
iso_checksum = "sha256:eafec62cfe760c30cac43f446463e628fada468c2de2f14e0e2bc27295187505"

# Bootstrap user — created by cloud-init autoinstall. Stage 2's ansible
# provisioner SSHes in as this user. Compliance role tightens or removes it.
ssh_username = "packer"

# Output filename. Version goes in the directory; the qcow2 itself has a
# stable name so symlinks like output/base/ubuntu2204-arm64/latest.qcow2
# are easy to maintain.
image_name_prefix = "ubuntu2204-arm64-base"
