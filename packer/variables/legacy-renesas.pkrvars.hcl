# Renesas-specific variables.
# Pairs with: templates/renesas-rhel9-hardened.pkr.hcl
#
# Compliance: CIS-L2 + FIPS 140-3 (RHEL 9 system-wide crypto-policy=FIPS).

tenant              = "renesas"
compliance_profile  = "cis-l2"
fips_mode           = "true"

# Base ISO. Override at runtime if you want a newer minor.
# Example for RHEL 9.4 DVD: download once, stash on a fileserver, point here.
iso_url      = "https://internal-mirror.renesas.local/isos/rhel-9.4-x86_64-dvd.iso"
# Set to a real sha256 from Red Hat before any production build.
# `none` lets `packer validate` pass structurally and Packer will emit a
# loud warning at build time. NEVER bake a prod image with checksum=none.
iso_checksum = "none"

# RHEL subscription credentials must NOT be hardcoded. Read from env in the
# template via `lookup('env', 'RHEL_USERNAME')`. Stub here so the var exists.
rhel_subscription_pool_id = ""

# Default username baked into the image. Real ansible runs use a per-tenant
# service account; this is just the bootstrap user Packer uses for SSH.
ssh_username = "packer"

# Banner text written to /etc/issue.net (used by sshd).
# Renesas legal-approved verbiage; coordinate with their security team
# before changing.
login_banner = "RENESAS // Authorized use only. All activity is logged and audited."

# Output box name pattern. Used by the build script to organize artifacts.
image_name_prefix = "renesas-rhel9-cisl2-fips"
