# Bosch ARM64 — STAGE 2 hardening variables.
# Pairs with: templates/bosch-ubuntu2204-arm64-hardened.pkr.hcl
#
# Compliance: CIS-L1 (no FIPS).
# Use case: local dev sandboxes on Apple Silicon Macs, future ARM64 server
# deployment. ARM64 is binary-incompatible with x86_64 hardware — never
# deploy this artifact to Intel/AMD servers.
#
# Stage 1's ISO/checksum live in variables/ubuntu-arm64-base.pkrvars.hcl now;
# this file no longer carries them. Stage 2 only cares about WHERE the base
# qcow2 lives (base_image_path) and the tenant-specific hardening knobs.

tenant              = "bosch"
compliance_profile  = "cis-l1"
fips_mode           = "false"

# Default bootstrap user — matches what stage 1 created via cloud-init.
# Compliance role rotates / disables this in post-tasks.
ssh_username = "packer"

# Banner text — Bosch legal-approved.
login_banner = "BOSCH // Authorized use only. All activity is logged and audited."

# Output box name pattern. Arch suffix prevents amd64/arm64 artifact name collision.
image_name_prefix = "bosch-ubuntu2204-cisl1-arm64"

# Default base image. scripts/build.sh overrides this via -var when STAGE=hardened
# is invoked with a different base path (e.g. an existing half-baked qcow2 you
# want to iterate against without re-baking the OS install).
#
# The default points at whatever stage 1 most recently produced under the
# canonical layout. If no base exists yet, build.sh refuses to run STAGE=hardened
# and tells you to run STAGE=base first.
base_image_path = "output/base/ubuntu2204-arm64/latest/ubuntu2204-arm64-base-latest.qcow2"
