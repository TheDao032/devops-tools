# Guest: Ubuntu 24.04 LTS (Noble Numbat) — amd64
# Paired with: templates/ubuntu-amd64.pkr.hcl
#
# To refresh when Ubuntu rolls a new point release:
#   1. Grab https://releases.ubuntu.com/24.04/SHA256SUMS
#   2. Copy the *-live-server-amd64.iso line's hash below
#   3. Update iso_filename to match the new point release

iso_filename = "ubuntu-24.04.4-live-server-amd64.iso"
# Verified 2026-07-08 against https://releases.ubuntu.com/24.04/SHA256SUMS.
iso_checksum = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
guest_slug   = "ubuntu2404"

ssh_username = "packer"
