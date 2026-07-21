# Ubuntu 24.04 LTS ARM64 — variables for the STAGE 1 base bake.
# Pairs with: templates/_base/ubuntu2404-arm64-base.pkr.hcl
#
# Produces a tenant-AGNOSTIC 24.04 base image. Tenant-specific values
# (compliance profile, banner, per-tenant image_name_prefix) live in
# variables/<org>/arm64.pkrvars.hcl and are consumed by stage 2.
#
# WHY 24.04 LTS (not 26.04): the 26.04.0 arm64 live-server ISO ships a kernel
# (7.0.0-14-generic) with a fatal OverlayFS bug — `ovl_iterate_merged` oopses
# during directory iteration, killing curtin's rsync mid-extract, so the
# install can never complete under qemu. Confirmed 2026-07-21 via serial-console
# capture. 24.04 LTS has a stable 6.x kernel, is supported to 2029, and is
# plenty modern for the personal k3s lab. Revisit 26.04 when a 26.04.1 point
# release ships with a fixed kernel.
#
# Refresh cadence: re-bake when Ubuntu cuts a 24.04 point release with security
# fixes you care about, OR quarterly, OR on demand. The base does NOT need a
# re-bake when the compliance role changes — that's stage 2.

# Ubuntu 24.04.4 LTS server ARM64 ("Noble Numbat").
# Cache the ISO locally first (matches the base convention):
#   curl -Lo ~/iso-cache/ubuntu-24.04.4-live-server-arm64.iso \
#     https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.4-live-server-arm64.iso
iso_url      = "file:///Users/thedao/iso-cache/ubuntu-24.04.4-live-server-arm64.iso"
iso_checksum = "sha256:9a6ce6d7e66c8abed24d24944570a495caca80b3b0007df02818e13829f27f32"

# Bootstrap user — created by cloud-init autoinstall. Stage 2's ansible
# provisioner SSHes in as this user. Compliance role tightens or removes it.
ssh_username = "packer"

# Output filename. Version goes in the directory; the qcow2 itself has a stable
# name so `latest` symlinks (output/base/ubuntu2404-arm64/latest/...) are easy.
image_name_prefix = "ubuntu2404-arm64-base"
