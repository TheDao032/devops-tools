# nthedao ARM64 — STAGE 2 hardening variables (personal lab line).
# Pairs with: templates/nthedao/ubuntu2404-arm64-hardened.pkr.hcl
#
# Compliance: CIS-L1 (no FIPS).
# Use case: the personal k3s-etcd QEMU lab on Apple Silicon. Published to
# Vagrant Cloud as nthedao2705/ubuntu2404-cisl1-arm64 and consumed by
# vagrant/vagrant-files/k3s/config.yaml. Replaces the old repackaged
# nthedao2705/ubuntu2204-cisl1-arm64 (which was the bosch 22.04 image).
#
# Stage 1's ISO/checksum live in variables/_base/ubuntu2404-arm64-base.pkrvars.hcl;
# this file only carries WHERE the base qcow2 lives (base_image_path) and the
# hardening knobs.

tenant             = "nthedao"
compliance_profile = "cis-l1"
fips_mode          = "false"

# Default bootstrap user — matches what stage 1 created via cloud-init.
# Compliance role rotates / disables this in post-tasks.
ssh_username = "packer"

# Banner text — personal lab.
login_banner = "nthedao lab // Authorized use only. Activity may be logged."

# Output box name pattern. Arch suffix prevents amd64/arm64 name collision.
# Matches the Vagrant Cloud box name nthedao2705/ubuntu2404-cisl1-arm64.
image_name_prefix = "nthedao-ubuntu2404-cisl1-arm64"

# Default base image. scripts/build.sh overrides this via -var when STAGE=hardened
# is invoked with a different base path. Points at whatever stage 1 most recently
# produced under the canonical layout (the latest/ symlink).
base_image_path = "output/base/ubuntu2404-arm64/latest/ubuntu2404-arm64-base-latest.qcow2"
